package main

import (
	"encoding/json"
	"fmt"
	"io"
	"time"
	"math/big"
	"net/http"
	"net/http/httptest"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/flashbots/suapp-examples/framework"
)

type Withdrawal struct {
	Index     uint64
	Validator uint64
	Address   common.Address
	Amount    uint64
}

type BlockArgs struct {
	Slot           uint64
	ProposerPubkey []byte
	Parent         common.Hash
	Timestamp      uint64
	FeeRecipient   common.Address
	GasLimit       uint64
	Random         common.Hash
	Withdrawals    []Withdrawal
}


func main() {
	fakeRelayer := httptest.NewServer(&relayHandlerExample{})
	defer fakeRelayer.Close()

	fr := framework.New()
	contract := fr.DeployContract("Pepc.sol/Pepc.json")

	// Step 1. Create and fund the accounts we are going to frontrun/backrun
	fmt.Println("1. Create and fund test accounts")

	testAddr1 := framework.GeneratePrivKey()
	testAddr2 := framework.GeneratePrivKey()

	fundBalance := big.NewInt(100000000000000000)
	fr.FundAccount(testAddr1.Address(), fundBalance)
	fr.FundAccount(testAddr2.Address(), fundBalance)

	targeAddr := testAddr1.Address()

	ethTxn1, _ := fr.SignTx(testAddr1, &types.LegacyTx{
		To:       &targeAddr,
		Value:    big.NewInt(1000),
		Gas:      21000,
		GasPrice: big.NewInt(13),
	})

	ethTxn2, _ := fr.SignTx(testAddr2, &types.LegacyTx{
		To:       &targeAddr,
		Value:    big.NewInt(1000),
		Gas:      21420,
		GasPrice: big.NewInt(13),
	})

	// Step 2. Send first bundle transation
	fmt.Println("2. Send first bundle")

	refundPercent := 10
	bundle := &types.SBundle{
		Txs:             types.Transactions{ethTxn1},
		RevertingHashes: []common.Hash{},
		RefundPercent:   &refundPercent,
	}
	bundleBytes, _ := json.Marshal(bundle)

	targetBlock := uint64(1)
	volume := new(big.Int)
  volume.SetString("200", 10)

	// new bid inputs
	contractAddr1 := contract.Ref(testAddr1)
	fmt.Println(contractAddr1.Address().String())
	allowedPeekers := []common.Address{}
	allowedPeekers = append(allowedPeekers, common.HexToAddress(contractAddr1.Address().String()))
	receipt := contractAddr1.SendTransaction("sendBundleTx", []interface{}{targetBlock + 1, allowedPeekers, allowedPeekers, volume}, bundleBytes)

	bundleEvent := &SendBundleEvent{}
	if err := bundleEvent.Unpack(receipt.Logs[0]); err != nil {
		panic(err)
	}

	fmt.Printf("First Bundle Bid Id: 0x%x\n", bundleEvent.BidId)
	fmt.Printf("First Bundle Data: 0x%x\n", bundleEvent.Bundle)

	// Step 3. Send second bundle transation
	fmt.Println("2. Send second bundle")

	secondBundle := &types.SBundle{
		Txs:             types.Transactions{ethTxn2},
		RevertingHashes: []common.Hash{},
	}
	secondBundleBytes, _ := json.Marshal(secondBundle)

	// backrun inputs
	contractAddr2 := contract.Ref(testAddr2)
	allowedPeekers = append(allowedPeekers, common.HexToAddress(contractAddr2.Address().String()))
	volume = new(big.Int)
	volume.SetString("100", 10)
	receipt = contractAddr2.SendTransaction("sendBundleTx", []interface{}{targetBlock + 1, allowedPeekers, allowedPeekers, volume}, secondBundleBytes)

	secondBundleEvent := &SendBundleEvent{}
	if err := secondBundleEvent.Unpack(receipt.Logs[0]); err != nil {
		panic(err)
	}

	fmt.Printf("First Bundle Bid Id: 0x%x\n", secondBundleEvent.BidId)
	fmt.Printf("First Bundle Data: 0x%x\n", secondBundleEvent.Bundle)

	// Step 4. Sort and send the bundle to the relayer
	fmt.Println("4. Sort and Send bundle to relayer")

	blockArgs := BlockArgs{
		Slot: uint64(1),
		ProposerPubkey: []byte(targeAddr.String()),
		Parent: common.HexToHash("0x524529737b6448c3803001db5ea2758d93da27520f794f65f69b92ad6934ef38"),
		Timestamp: uint64(time.Now().Unix()),
		FeeRecipient: common.HexToAddress(targeAddr.String()),
		GasLimit: uint64(1000000),
		Random: common.HexToHash("0x1234"),
		Withdrawals: []Withdrawal{},
	}

	receipt = contractAddr1.SendTransaction("buildTOB", []interface{}{targetBlock + 1, blockArgs}, []byte{})

	buildBlock := &BuildBlockEvent{}
	if err := buildBlock.Unpack(receipt.Logs[0]); err != nil {
		panic(err)
	}

}

var sendBundleTxABI abi.Event
var buildBlockABI abi.Event

func init() {
	artifact, _ := framework.ReadArtifact("Pepc.sol/Pepc.json")
	sendBundleTxABI = artifact.Abi.Events["SendBundleTx"]
	buildBlockABI = artifact.Abi.Events["BuildBlock"]
}

type SendBundleEvent struct {
	BidId [16]byte
	Bundle  []byte
}

type BuildBlockEvent struct {
	BidId [16]byte
	Data  []byte
}

func (b *SendBundleEvent) Unpack(log *types.Log) error {
	unpacked, err := sendBundleTxABI.Inputs.Unpack(log.Data)
	if err != nil {
		return err
	}
	b.BidId = unpacked[0].([16]byte)
	b.Bundle = unpacked[1].([]byte)
	return nil
}

func (b *BuildBlockEvent) Unpack(log *types.Log) error {
	unpacked, err := buildBlockABI.Inputs.Unpack(log.Data)
	if err != nil {
		return err
	}
	b.BidId = unpacked[0].([16]byte)
	b.Data = unpacked[1].([]byte)
	return nil
}

type relayHandlerExample struct {
}

func (rl *relayHandlerExample) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil {
		panic(err)
	}

	fmt.Println(string(bodyBytes))
}
