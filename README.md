# pepc-rep

- Challenges

  - ¹ Proposer has limited flexibility and cannot express preferences such as what style of bid to take.
  - ² Bid may disadvantage SwapX TXs that are on top because the searcher's bundle, which should be on top, is not on top.
  - ³ Direct Fill of UniswapX (e.g., when canceling) requires trusting the filler. Also, there is a possibility that the builder colludes and does not take direct fills that do not pass bid into the block. This is expected to lead to bundles in which MEVs are not reduced to the
    - Currently, Uniswap X direct fills are managed in a centralized manner, and direct fills do not pass bids.
    - ExclusiveDutchOrderReactor : https://etherscan.io/address/0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4

- Solution
  - ¹ PEPC-REP: Design a more flexible and diverse communication market where the proposer exerts preference in the construction of the block, which is detected by the searcher and the TOB Bid is submitted.
  - ² Auction the rights to the first transaction per block through an auction of smart contracts. Searcher sends a Bundle to Uni V4 via SUAVE, which always makes the tx of the DEX-CEX arb the first of the block, returns a portion of the bid to the AMM, returns the price of DEX to some extent with searcher's tx in the relevant block, and the subsequent Swapper's Swap can be performed at a reasonable price.
  - ³ Direct fill signatures can be received in SUAVE and Dutch auction can be implemented in MEVM to implement UniswapX direct fill in a more trustless way.
    - Improved transparency: no transparency since the Dutch auction is done off-chain; the signature data of Intents is kept confidential on Suave, so it can be cancelled in a trustless manner.
    - Inclusion of secure Direct Fill in the block: got price at t=12, but Dex - fill arb can be done before t=12; Direct Fill does not pass bid; Dex-cex arb does; Direct Fill is not accepted The builder can do attacks such as "I don't accept Direct Fill", so Direct Fill on SUAVE is passed as bid.
    - This is likely to happen more often in the future with Intents base apps, including Uniswap V4 and X. Since revenue is no longer passed on to actors in the traditional MEV-boost supply chain, the PEPC-REP can become the execution environment for these Intents base applications to collect more order flows and attract more order flow and gain an advantage over other builders.
    - Provide the PEPC-REP as a more trustless execution environment when fraud occurs, even if it does not win.

# SUAVE Suapp Examples

This repository contains several [examples and useful references](/examples/) for building Suapps!

---

See also:

- **https://github.com/flashbots/suave-geth**
- https://collective.flashbots.net/c/suave/27

Writings:

- https://writings.flashbots.net/the-future-of-mev-is-suave
- https://writings.flashbots.net/mevm-suave-centauri-and-beyond

---

## Getting Started

```bash
# Clone this repository
$ git clone git@github.com:flashbots/suapp-examples.git

# Checkout the suave-geth submodule
$ git submodule init
$ git submodule update
```

---

## Compile the examples

Install [Foundry](https://getfoundry.sh/):

```
$ curl -L https://foundry.paradigm.xyz | bash
```

Compile:

```bash
$ forge build
```

---

## Start the local devnet

See the instructions here: https://github.com/flashbots/suave-geth#starting-a-local-devnet

---

## Run the examples

Check out the [`/examples/`](/examples/) folder for several example Suapps and `main.go` files to deploy and run them!

---

Happy hacking 🛠️
