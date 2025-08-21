# DeFi Stablecoin

This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.

# Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2025-08-16T00:05:26.396218Z)`

## Quickstart

```js
git clone https://github.com/nwachee/foundDeFI.git
cd foundDeFi
forge build
```

# Usage

## Start a local node

```
make anvil
```

## Deploy

This will default to your local node. You need to have it running in another terminal in order for it to deploy.

```
make deploy
```

## Testing
```
forge test
```

or

```
forge test --fork-url $SEPOLIA_RPC_URL
```

### Test Coverage

```
forge coverage
```

# Deployment to a testnet or mainnet

#### 1. **Setup environment variables**

Create a ```.env``` file in the root folder:

```js
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
PRIVATE_KEY=your_private_key_without_0x
ETHERSCAN_API_KEY=your_etherscan_api_key
```

**NOTE: FOR DEVELOPMENT, PLEASE USE A PRIVATE KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.**

#### 2. **Deploy**

```
make deploy ARGS="--network sepolia"
```