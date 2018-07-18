pragma solidity ^0.4.21;

import "./CueAccessControl.sol";
import "./SaleClockAuction.sol";

/// @title Base contract for CryptoCues. Holds all common structs, events and base variables.
/// @author SecureBlocks.io
/// @dev See the CueCore contract documentation to understand how the various contract facets are arranged.
contract CueBase is CueAccessControl {
    /*** EVENTS ***/

    /// @dev The Manufactured event is fired whenever a new cue comes into existence. This obviously
    ///  includes any time a cue is created through the remanufacture method, but it is also called
    ///  when a new GEN0 cue is created.
    event Manufactured(address owner, uint256 cueId, uint256 firstParentId, uint256 secondParentId, uint256 thirdParentId, string genes);

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a cue
    ///  ownership is assigned, including remanufacture.
    event Transfer(address from, address to, uint256 tokenId);

    /*** DATA TYPES ***/

    /// @dev The main Cue struct. Every cue in CryptoCues is represented by a copy
    ///  of this structure, so great care was taken to ensure that it fits neatly into
    ///  exactly two 256-bit words. Note that the order of the members in this structure
    ///  is important because of the byte-packing rules used by Ethereum.
    ///  Ref: http://solidity.readthedocs.io/en/develop/miscellaneous.html
    struct Cue {
        // The Cue's genetic code is packed into these 256-bits, the format is
        // sooper-sekret! A cue's genes never change.
        string genes;

        // The timestamp from the block when this cue came into existence.
        uint64 birthTime;

        // The minimum timestamp after which this cue can engage in remanufacturing
        // activities again. This same timestamp is used for the cooldown.
        uint64 cooldownEndBlock;

        // The ID of the parents of this cue.
        uint32 firstParentId;
        uint32 secondParentId;
        uint32 thirdParentId;

        // Set to the index in the cooldown array (see below) that represents
        // the current cooldown duration for this cue. 
        uint16 cooldownIndex;
    }

    /*** CONSTANTS ***/

    /// @dev A lookup table indicating the cooldown duration after any successful
    ///  remanufacturing action. Designed such that the cooldown roughly doubles each time a cue 
    ///  remanufacture. Caps out at one week (a cue can remanufacture an unbounded number
    ///  of times, and the maximum cooldown is always seven days).
    uint32[14] public cooldowns = [
        uint32(1 minutes),
        uint32(2 minutes),
        uint32(5 minutes),
        uint32(10 minutes),
        uint32(30 minutes),
        uint32(1 hours),
        uint32(2 hours),
        uint32(4 hours),
        uint32(8 hours),
        uint32(16 hours),
        uint32(1 days),
        uint32(2 days),
        uint32(4 days),
        uint32(7 days)
    ];

    // An approximation of currently how many seconds are in between blocks.
    uint256 public secondsPerBlock = 15;

    /*** STORAGE ***/

    /// @dev An array containing the Cue struct for all cues in existence. The ID
    ///  of each cue is actually an index into this array.
    Cue[] cues;

    /// @dev A mapping from cue IDs to the address that owns them. All cues have
    ///  some valid owner address, even GEN0 cues are created with a non-zero owner.
    mapping (uint256 => address) public cueIndexToOwner;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping (address => uint256) ownershipTokenCount;

    /// @dev A mapping from CueIDs to an address that has been approved to call
    ///  transferFrom(). Each cue can only have one approved address for transfer
    ///  at any time. A zero value means no approval is outstanding.
    mapping (uint256 => address) public cueIndexToApproved;

    /// @dev A mapping from CueIDs to an address that has been approved to use
    ///  this cue for remanufacture. Each cue can only have one approved
    ///  address for remanufacture at any time. A zero value means no approval is outstanding.
    mapping (uint256 => address) public remanufactureAllowedToAddress;

    /// @dev The address of the ClockAuction contract that handles sales of Cues. This
    ///  same contract handles both peer-to-peer sales as well as the gen0 sales which are
    ///  initiated every 15 minutes.
    SaleClockAuction public saleAuction;

    /// @dev Assigns ownership of a specific cue to an address.
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // Since the number of cues is capped to 2^32 we can't overflow this
        ownershipTokenCount[_to]++;
        // transfer ownership
        cueIndexToOwner[_tokenId] = _to;
        // When creating new cue _from is 0x0, but we can't account that address.
        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
            // once the cue is transferred also clear remanufacture allowances
            delete remanufactureAllowedToAddress[_tokenId];
            // clear any previously approved ownership exchange
            delete cueIndexToApproved[_tokenId];
        }
        // Emit the transfer event.
        emit Transfer(_from, _to, _tokenId);
    }

    /// @dev An internal method that creates a new cue and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both Remanufacture event
    ///  and a Transfer event.
    /// @param _firstParentId The cue ID of the first parent of this cue
    /// @param _secondParentId The cue ID of the second parent of this cue
    /// @param _thirdParentId The cue ID of the third parent of this cue
    /// @param _genes The cue's genetic code.
    /// @param _owner The inital owner of this cue, must be non-zero
    function _createCue(
        uint256 _firstParentId,
        uint256 _secondParentId,
        uint256 _thirdParentId,
        string  _genes,
        address _owner
    )
        internal
        returns (uint)
    {
        // These requires are not strictly necessary, our calling code should make
        // sure that these conditions are never broken. However! _createCue() is already
        // an expensive call (for storage), and it doesn't hurt to be especially careful
        // to ensure our data structures are always valid.
        require(_firstParentId == uint256(uint32(_firstParentId)));
        require(_secondParentId == uint256(uint32(_secondParentId)));
        require(_thirdParentId == uint256(uint32(_thirdParentId)));

        uint16 cooldownIndex = 0;
        // uint16 cooldownIndex = uint16(_generation / 2);
        // if (cooldownIndex > 13) {
        //     cooldownIndex = 13;
        // }

        Cue memory _cue = Cue({
            genes: _genes,
            birthTime: uint64(now),
            cooldownEndBlock: 0,
            firstParentId: uint32(_firstParentId),
            secondParentId: uint32(_secondParentId),
            thirdParentId: uint32(_thirdParentId),
            cooldownIndex: cooldownIndex
        });
        uint256 newCueId = cues.push(_cue) - 1;

        // It's probably never going to happen, 4 billion cues is A LOT, but
        // let's just be 100% sure we never let this happen.
        require(newCueId == uint256(uint32(newCueId)));

        // emit the birth event
        emit Manufactured(
            _owner,
            newCueId,
            uint256(_cue.firstParentId),
            uint256(_cue.secondParentId),
            uint256(_cue.thirdParentId),
            _cue.genes
        );

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(0, _owner, newCueId);

        return newCueId;
    }

    // Any C-level can fix how many seconds per blocks are currently observed.
    function setSecondsPerBlock(uint256 secs) external onlyCLevel {
        require(secs < cooldowns[0]);
        secondsPerBlock = secs;
    }
}