pragma solidity ^0.4.23;

import "./CueRemanufacture.sol";

/// @title Handles creating auctions for sale and lending of cues.
///  This wrapper of ReverseAuction exists only so that users can create
///  auctions with only one transaction.
contract CueAuction is CueRemanufacture {

    // @notice The auction contract variables are defined in CueBase to allow
    //  us to refer to them in CueOwnership to prevent accidental transfers.
    // `saleAuction` refers to the auction for GEN0 and p2p sale of cues.

    /// @dev Sets the reference to the sale auction.
    /// @param _address - Address of sale contract.
    function setSaleAuctionAddress(address _address) external onlyCEO {
        SaleClockAuction candidateContract = SaleClockAuction(_address);

        // NOTE: verify that a contract is what we expect - https://github.com/Lunyr/crowdsale-contracts/blob/cfadd15986c30521d8ba7d5b6f57b4fefcc7ac38/contracts/LunyrToken.sol#L117
        require(candidateContract.isSaleClockAuction());

        // Set the new contract address
        saleAuction = candidateContract;
    }

    /// @dev Put a cue up for auction.
    ///  Does some ownership trickery to create auctions in one tx.
    function createSaleAuction(
        uint256 _cueId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration
    )
        external
        whenNotPaused
    {
        // Auction contract checks input sizes
        // If cue is already on any auction, this will throw
        // because it will be owned by the auction contract.
        require(_owns(msg.sender, _cueId));
        // NOTE: the cue is allowed to be in a cooldown.
        _approve(_cueId, saleAuction);
        // Sale auction throws if inputs are invalid and clears
        // transfer after escrowing the cue.
        saleAuction.createAuction(
            _cueId,
            _startingPrice,
            _endingPrice,
            _duration,
            msg.sender
        );
    }

    /// @dev Transfers the balance of the sale auction contract
    /// to the CueCore contract. We use two-step withdrawal to
    /// prevent two transfer calls in the auction bid function.
    function withdrawAuctionBalances() external onlyCLevel {
        saleAuction.withdrawBalance();
    }
}