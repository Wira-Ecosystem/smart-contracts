## Wira Wallet

**Wira wallet is an AA wallet designed to make blockhain interactios easier for the users**

## Usage

Once the repository is cloned, install the openZeppelin and account abstraction dependencies

```shell
$ forge install OpenZeppelin/openzeppelin-contracts
$ forge install eth-infinitism/account-abstraction@v0.7.0
```

Next install the Chainlink CCIP dependences, this doesn't require to have a node project inside

```shell
$ npm install
```

### Format

```shell
$ forge fmt
```

### Test
Is mandatory to use a forked network for testing

```shell
$ forge test --fork-url <your_rpc_url>
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/WalletAccountFactory.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast -vvvv
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
