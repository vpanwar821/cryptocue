const CueCore = artifacts.require('./CueCore.sol')
const SaleClockAuction = artifacts.require('./SaleClockAuction.sol')

contract('CueCore', accounts => {

    let cueCore;
    let saleClockAuction;

    const owner = accounts[0]
    const buyer = accounts[1];

    before(async() => {
        cueCore = await CueCore.new( {from: owner})
        saleClockAuction = await SaleClockAuction.new(cueCore.address, 0, {from: owner})
        await cueCore.setSaleAuctionAddress(saleClockAuction.address, { from: owner })
        await cueCore.unpause({from: owner})
    })

    describe('Test Cases for the create new auction function', async () => {

        it('createGen0Auction: Should successfully create the new cue', async () => {
            let cueId = await cueCore.createGen0Auction("qwerty", { from : owner })
            assert.equal(await cueCore.gen0CreatedCount(), 1)
            
            let cue = await cueCore.getCue(0)
            assert.equal(cue[6], "qwerty")

            let auction = await saleClockAuction.getAuction(0)
            assert.equal(auction[0], cueCore.address)

            await saleClockAuction.bid(0, {from : buyer, value: web3.toWei('1', 'ether')})

            let own = await cueCore.ownerOf(0)
            console.log(own)
            console.log(buyer)
            
        })
    })
    
})