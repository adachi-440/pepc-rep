// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Suave} from "../../suave-geth/suave/sol/libraries/Suave.sol";

// Uncomment this line to use console.log
import "forge-std/console.sol";

contract Pepc {
    string public boostRelayUrl = "https://relay-goerli.flashbots.net";

    struct Bundle {
        Suave.BidId bidId;
        bytes data;
    }

    struct BuiltBlock {
        Suave.BidId bidId;
        bytes data;
    }

    mapping(address => address) public preferences; // proposer => tokenAddress
    mapping(Suave.BidId => bool) public isRegistered; // bidId => bool

    event RegisterPreference(address proposer, address token);
    event SendBundleTx(Suave.BidId bidId, bytes bundleData);
    event BuildBlock(Suave.BidId bidId, bytes builderBid);
    event BidEvent(Suave.BidId bidId, uint64 decryptionCondition, address[] allowedPeekers);

    error InvalidAddress();

    /**
     * @dev Register the token address that the proposer wants to receive as a reward.
     * @param _proposer The address of the proposer.
     * @param _token The address of the token that the proposer wants to receive as a reward.
     * @notice The proposer can register only one token address.
     */
    function registerPreference(address _proposer, address _token) external {
        if (_proposer == address(0) || _token == address(0)) {
            revert InvalidAddress();
        }

        preferences[_proposer] = _token;

        emit RegisterPreference(_proposer, _token);
    }

    /**
     * @dev Get the token address that the proposer wants to receive as a reward.
     * @param _proposer The address of the proposer.
     * @notice If the proposer has not registered the token address, the zero address will be returned.
     */
    function getPreference(address _proposer) external view returns (address) {
        return preferences[_proposer];
    }

    function emitSendBundleTx(Bundle memory bundle) public payable {
        emit SendBundleTx(bundle.bidId, bundle.data);
    }

    /**
     * @dev Send the bundle transaction to the confidential datastore.
     * @param decryptionCondition The decryption condition of the bundle.
     * @param bidAllowedPeekers The addresses of the peekers that are allowed to peek the bundle.
     * @param bidAllowedStores The addresses of the stores that are allowed to store the bundle.
     * @notice The proposer can register only one token address.
     */
    function sendBundleTx(
      uint64 decryptionCondition,
      address[] memory bidAllowedPeekers,
      address[] memory bidAllowedStores,
      uint256 volume
      ) external payable returns (bytes memory) {
        // Retrieve the bundle data from the confidential inputs
        bytes memory bundleData = Suave.confidentialInputs();

        // Store the bundle and the simulation results in the confidential datastore.
		    Suave.Bid memory bid = Suave.newBid(decryptionCondition, bidAllowedPeekers, bidAllowedStores, "pepc:v0:uncheckedBundles");
        Suave.confidentialStore(bid.id, "pepc:v0:ethBundles", bundleData);
        Suave.confidentialStore(bid.id, "pepc:v0:volumes", abi.encodePacked(volume));
        isRegistered[bid.id] = false;

        Bundle memory bundle;
        bundle.bidId = bid.id;
        bundle.data = bundleData;

        return abi.encodeWithSelector(this.emitSendBundleTx.selector, bundle);
    }

    /**
     * @dev Select the TOB from the bundle transactions.
     * @param blockHeight The block height to select the TOB.
     * @param blockArgs The arguments to build the TOB.
     * @notice The proposer can register only one token address.
     */
    function buildTOB(uint64 blockHeight, Suave.BuildBlockArgs memory blockArgs) external payable returns (bytes memory) {
        Suave.Bid[] memory allUncheckedBids = Suave.fetchBids(blockHeight, "pepc:v0:uncheckedBundles");

        Suave.Bid[] memory allBids = new Suave.Bid[](allUncheckedBids.length);

        // Bubble sort the bids by volume
        uint n = allUncheckedBids.length;
        for (uint i = 0; i < n; i++) {
          for (uint j = i + 1; j < n; j++) {
            Suave.Bid memory bid = allUncheckedBids[i];
            Suave.Bid memory nextBid = allUncheckedBids[j];

            if(isRegistered[bid.id]) continue;

            uint256 volume = abi.decode(Suave.confidentialRetrieve(bid.id, "pepc:v0:volumes"), (uint256));
            uint256 nextVolume = abi.decode(Suave.confidentialRetrieve(nextBid.id, "pepc:v0:volumes"), (uint256));

            if (volume < nextVolume) {
              allBids[i] = nextBid;
              allBids[j] = bid;
            }
            isRegistered[bid.id] = true;
          }
        }

        Suave.BidId[] memory allBidIds = new Suave.BidId[](allBids.length);
        for (uint i = 0; i < allBids.length; i++) {
          allBidIds[i] = allBids[i].id;
        }
        console.log("allBidIds.length");
        console.log(allBidIds.length);

        return buildAndEmit(blockArgs, blockHeight, allBidIds, "pepc:v0");
    }

    function emitBuildBlock(BuiltBlock memory builtBlock) public payable {
        emit BuildBlock(builtBlock.bidId, builtBlock.data);
    }

    function buildAndEmit(Suave.BuildBlockArgs memory blockArgs, uint64 blockHeight, Suave.BidId[] memory bids, string memory namespace) public virtual returns (bytes memory) {

		(Suave.Bid memory blockBid, bytes memory builderBid) = this.doBuild(blockArgs, blockHeight, bids, namespace);
		Suave.submitEthBlockBidToRelay(boostRelayUrl, builderBid);

		BuiltBlock memory builtBlock;
    builtBlock.bidId = blockBid.id;
    builtBlock.data = builderBid;

		return abi.encodeWithSelector(this.emitSendBundleTx.selector, builtBlock);
	}

    function emitBid(Suave.Bid calldata bid) public payable {
		  emit BidEvent(bid.id, bid.decryptionCondition, bid.allowedPeekers);
	}

  function doBuild(Suave.BuildBlockArgs memory blockArgs, uint64 blockHeight, Suave.BidId[] memory bids, string memory namespace) public view returns (Suave.Bid memory, bytes memory) {
		address[] memory allowedPeekers = new address[](2);
		allowedPeekers[0] = address(this);
		allowedPeekers[1] = Suave.BUILD_ETH_BLOCK;

		Suave.Bid memory blockBid = Suave.newBid(blockHeight, allowedPeekers, allowedPeekers, "default:v0:mergedBids");
		Suave.confidentialStore(blockBid.id, "default:v0:mergedBids", abi.encode(bids));

		(bytes memory builderBid, bytes memory payload) = Suave.buildEthBlock(blockArgs, blockBid.id, namespace);
		Suave.confidentialStore(blockBid.id, "pepc:v0:builderPayload", payload); // only through this.unlock

		return (blockBid, builderBid);
	}
}