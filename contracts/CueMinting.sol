pragma solidity ^0.4.23;

import "./CueAuction.sol";

/// @title all functions related to creating kittens
contract CueMinting is CueAuction {

    // Limits the number of cats the contract owner can ever create.
    uint256 public constant GEN0_CREATION_LIMIT = 50000;

    // Constants for GEN0 auctions.
    uint256 public constant GEN0_STARTING_PRICE = 10 finney;
    uint256 public constant GEN0_AUCTION_DURATION = 1 days;

    // Counts the number of cues the contract owner has created.
    uint256 public gen0CreatedCount;

    /// @dev Creates a new GEN0 cue with the given genes and
    ///  creates an auction for it.
    function createGen0Auction(string _genes) external onlyCOO returns (uint256) {
        require(gen0CreatedCount < GEN0_CREATION_LIMIT);

        uint256 cueId = _createCue(0, 0, 0, _genes, address(this));
        _approve(cueId, saleAuction);

        saleAuction.createAuction(
            cueId,
            _computeNextGen0Price(),
            0,
            GEN0_AUCTION_DURATION,
            address(this)
        );

        gen0CreatedCount++;

        return cueId;
    }

    /// @dev Computes the next GEN0 auction starting price, given
    ///  the average of the past 5 prices + 50%.
    function _computeNextGen0Price() internal view returns (uint256) {
        uint256 avePrice = saleAuction.averageGen0SalePrice();

        // Sanity check to ensure we don't overflow arithmetic
        require(avePrice == uint256(uint128(avePrice)));

        uint256 nextPrice = avePrice + (avePrice / 2);

        // We never auction for less than starting price
        if (nextPrice < GEN0_STARTING_PRICE) {
            nextPrice = GEN0_STARTING_PRICE;
        }

        return nextPrice;
    }
}