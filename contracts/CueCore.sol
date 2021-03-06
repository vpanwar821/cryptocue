pragma solidity ^0.4.23;

import "./CueMinting.sol";

/// @title CryptoCues: Collectible cues on the Ethereum blockchain.
/// @author SecureBlocks.io
/// @dev The main CryptoCues contract, keeps track of cues.
contract CueCore is CueMinting {

    // This is the main CryptoCues contract. In order to keep our code seperated into logical sections,
    // we've broken it up in two ways. First, we have several seperately-instantiated sibling contracts
    // that handle auctions and our super-top-secret genetic combination algorithm. The auctions are
    // seperate since their logic is somewhat complex and there's always a risk of subtle bugs. By keeping
    // them in their own contracts, we can upgrade them without disrupting the main contract that tracks
    // cue ownership. The genetic combination algorithm is kept seperate so we can open-source all of
    // the rest of our code without making it _too_ easy for folks to figure out how the genetics work.
    //
    // Secondly, we break the core contract into multiple files using inheritence, one for each major
    // facet of functionality of CC. This allows us to keep related code bundled together while still
    // avoiding a single giant file with everything in it. The breakdown is as follows:
    //
    //      - CueAccessControl: This contract manages the various addresses and constraints for operations
    //             that can be executed only by specific roles. Namely CEO, CFO and COO.
    // 
    //      - CueBase: This is where we define the most fundamental code shared throughout the core
    //             functionality. This includes our main data storage, constants and data types, plus
    //             internal functions for managing these items.
    //
    //      - CueOwnership: This provides the methods required for basic non-fungible token
    //             transactions, following the draft ERC-721 spec (https://github.com/ethereum/EIPs/issues/721).
    //
    //      - CueRemanufacture: This file contains the methods necessary to remanufacture cues
    //             and relies on an external genetic combination contract.
    //
    //      - CueAuctions: Here we have the public methods for auctioning or bidding on cues or lending
    //             services. The actual auction functionality is handled in two sibling contracts (one
    //             for sales and one for lending), while auction creation and bidding is mostly mediated
    //             through this facet of the core contract.
    //
    //      - CueMinting: This final facet contains the functionality we use for creating new gen0 cues.
    //             We can make up to 50000 cues that are created and then immediately put up
    //             for auction via an algorithmically determined starting price. Regardless of how they
    //             are created, there is a hard limit of 50k gen0 cues. After that, it's all up to the
    //             community to remanufacture!

    // Set in case the core contract is broken and an upgrade is required
    address public newContractAddress;

    /// @notice Creates the main CryptoCues smart contract instance.
    constructor() public {
        // Starts paused.
        paused = true;

        // the creator of the contract is the initial CEO
        ceoAddress = msg.sender;

        // the creator of the contract is also the initial COO
        cooAddress = msg.sender;

        // start with the cue 0 - so we don't have generation-0 parent issues
        // _createCue(0, 0, 0, uint256(-1), address(0));
    }

    /// @dev Used to mark the smart contract as upgraded, in case there is a serious
    ///  breaking bug. This method does nothing but keep track of the new contract and
    ///  emit a message indicating that the new address is set. It's up to clients of this
    ///  contract to update to the new contract address in that case. (This contract will
    ///  be paused indefinitely if such an upgrade takes place.)
    /// @param _v2Address new address
    function setNewAddress(address _v2Address) external onlyCEO whenPaused {
        // See README.md for updgrade plan
        newContractAddress = _v2Address;
        emit ContractUpgrade(_v2Address);
    }

    /// @notice No tipping!
    /// @dev Reject all Ether from being sent here, unless it's from one of the
    ///  two auction contracts. (Hopefully, we can prevent user accidents.)
    function() external payable {
        // require(
        //     msg.sender == address(saleAuction) ||
        //     msg.sender == address(siringAuction)
        // );
    }

    /// @notice Returns all the relevant information about a specific cue.
    /// @param _id The ID of the cue of interest.
    function getCue(uint256 _id)
        external
        view
        returns (
        uint256 cooldownIndex,
        uint256 nextActionAt,
        uint256 birthTime,
        uint256 firstParentId,
        uint256 secondParentId,
        uint256 thirdParentId,
        string  genes
    ) {
        Cue storage cue = cues[_id];

        cooldownIndex = uint256(cue.cooldownIndex);
        nextActionAt = uint256(cue.cooldownEndBlock);
        birthTime = uint256(cue.birthTime);
        firstParentId = uint256(cue.firstParentId);
        secondParentId = uint256(cue.secondParentId);
        thirdParentId = uint256(cue.thirdParentId);
        genes = cue.genes;
    }

    /// @dev Override unpause so it requires all external contract addresses
    ///  to be set before contract can be unpaused. Also, we can't have
    ///  newContractAddress set either, because then the contract was upgraded.
    /// @notice This is public rather than external so we can call super.unpause
    ///  without using an expensive CALL.
    function unpause() public onlyCEO whenPaused {
        // require(saleAuction != address(0));
        // require(siringAuction != address(0));
        require(newContractAddress == address(0));

        // Actually unpause the contract.
        super.unpause();
    }

    // @dev Allows the CFO to capture the balance available to the contract.
    function withdrawBalance() external onlyCFO {
        uint256 balance = this.balance;
        
        if (balance > 0) {
            cfoAddress.send(balance);
        }
    }
}