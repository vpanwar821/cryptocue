pragma solidity ^0.4.21;

import "./CueOwnership.sol";


/// @title A facet of CueCore that manages cue remanufacture
/// @author SecureBlocks.io
/// @dev See the CueCore contract documentation to understand how the various contract facets are arranged.
contract CueRemanufacture is CueOwnership {

    /// @notice The minimum payment required to use remanufactureCue(). This fee goes towards
    ///  the gas cost paid by whatever calls remanufacture(), and can be dynamically updated by
    ///  the COO role as the gas price changes.
    uint256 public remanufactureFee = 2 finney;

    /// @dev Checks that a given cue is able to remanufacture. Requires that the
    ///  current cooldown is finished (for all 3 cues)
    function _isReadyToManufacture(Cue _cue) internal view returns (bool) {
        return (_cue.cooldownEndBlock <= uint64(block.number));
    }

    /// @dev Set the cooldownEndTime for the given cue, based on its current cooldownIndex.
    ///  Also increments the cooldownIndex (unless it has hit the cap).
    /// @param _cue A reference to the cue in storage which needs its timer started.
    function _triggerCooldown(Cue storage _cue) internal {
        // Compute an estimation of the cooldown time in blocks (based on current cooldownIndex).
        _cue.cooldownEndBlock = uint64((cooldowns[_cue.cooldownIndex]/secondsPerBlock) + block.number);

        // Increment the count, clamping it at 13, which is the length of the
        // cooldowns array. We could check the array size dynamically, but hard-coding
        // this as a constant saves gas. Yay, Solidity!
        if (_cue.cooldownIndex < 13) {
            _cue.cooldownIndex += 1;
        }
    }

    /// @dev Updates the minimum payment required for calling remanufactureCue(). Can only
    ///  be called by the COO address. (This fee is used to offset the gas cost incurred
    ///  by the remanufactureCue daemon).
    function setRemanufactureFee(uint256 val) external onlyCOO {
        remanufactureFee = val;
    }

    /// @dev Internal check to see if a given sire and matron are a valid mating pair. DOES NOT
    ///  check ownership permissions (that is up to the caller).
    function _isValidForRemanufacture(
        Cue storage firstParent, 
        uint256 _firstParentId, 
        Cue storage secondParent, 
        uint256 _secondParentId, 
        Cue storage thirdParent, 
        uint256 _thirdParentId
    )
        private
        view
        returns(bool)
    {
        // Check all 3 ids are different
        if (_firstParentId == _secondParentId || _firstParentId == _thirdParentId || _secondParentId == _thirdParentId) {
            return false;
        }

        // Check to see if any of the cue is in cooldown period
        if (!_isReadyToManufacture(firstParent) || !_isReadyToManufacture(secondParent) || !_isReadyToManufacture(thirdParent)) {
            return false;
        }

        // Everything seems cool!
        return true;
    }

    /// @notice Checks to see if three cues can remanufacture, including checks for
    ///  ownership and remanufacture approvals.
    /// @param _firstParentId The ID of the first cue to use.
    /// @param _secondParentId The ID of the second cue to use.
    /// @param _thirdParentId The ID of the third cue to use.
    function canRemanufacture(uint256 _firstParentId, uint256 _secondParentId, uint256 _thirdParentId)
        external
        view
        returns(bool)
    {
        require(_firstParentId > 0);
        require(_secondParentId > 0);
        require(_thirdParentId > 0);
        Cue storage firstParent = cues[_firstParentId];
        Cue storage secondParent = cues[_secondParentId];
        Cue storage thirdParent = cues[_thirdParentId];
        return _isValidForRemanufacture(firstParent, _firstParentId, secondParent, _secondParentId, thirdParent, _thirdParentId);
    }

    /// @notice Refanufacture a new Cue using three of the cues you own. Will either make a new 
    /// cue, or will fail entirely. Requires a pre-payment of the fee.
    /// @param _firstParentId The ID of the first cue to use.
    /// @param _secondParentId The ID of the second cue to use.
    /// @param _thirdParentId The ID of the third cue to use.
    /// @param _genes The genes of the new cue to be created
    /// @dev Looks at a given cues and, if the gestation period has passed, use the 
    ///  combined genes of the three cues to create a new cue. The new Cue is assigned
    ///  to the caller of this function.
    function cueRemanufacture(uint256 _firstParentId, uint256 _secondParentId, uint256 _thirdParentId, string _genes)
        external
        payable
        whenNotPaused
        returns(uint256)
    {
        require(_firstParentId > 0);
        require(_secondParentId > 0);
        require(_thirdParentId > 0);
        require(bytes(_genes).length > 0);
        
        // Grab a reference of cue        
        Cue storage firstParent = cues[_firstParentId];
        Cue storage secondParent = cues[_secondParentId];
        Cue storage thirdParent = cues[_thirdParentId];
        
        // Checks for payment.
        // require(msg.value >= remanufactureFee);

        // Caller must own all of the three cues.
        require(_owns(msg.sender, _firstParentId));
        require(_owns(msg.sender, _secondParentId));
        require(_owns(msg.sender, _thirdParentId));

        // Check that all cues are valid.
        require(firstParent.birthTime != 0);
        require(secondParent.birthTime != 0);
        require(thirdParent.birthTime != 0);

        // Check if remenufacture is allowed
        require(_isValidForRemanufacture(firstParent, _firstParentId, secondParent, _secondParentId, thirdParent, _thirdParentId));

        // All checks passed, start cooldown of cues
        _triggerCooldown(firstParent);
        _triggerCooldown(secondParent);
        _triggerCooldown(thirdParent);

        // Create a new cue

        address owner = cueIndexToOwner[_firstParentId];
        uint256 cueId = _createCue(_firstParentId, _secondParentId, _thirdParentId, _genes, owner);

        // Send the balance fee to the person who made birth happen.
        // msg.sender.send(remanufactureFee);

        // return the new kitten's ID
        return cueId;
    }
}