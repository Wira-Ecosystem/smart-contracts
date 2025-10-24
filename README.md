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

## Technical Limits

- For multichain, a user can have the same SmartWallet address on several networks, as long as that SmartWallet is created with the same owner address, has the same salt, and the factory also has the same address.

- The factory must have the same code and be deployed by the same wallet to have the same address on all networks.

- The factory cannot be made upgradable; this actually doesn't make sense. If we wanted to add, for example, a spend credit to the user for creating the wallet, this only affects the new ones. So we simply deploy a new factory.

- If Base paymaster will be used, it's nedded to use their Smart Wallets, so the factory wouldn't exist and new functions can't be added.

- Users can recover access on all networks with their owner address and salt saved on recovery servers.