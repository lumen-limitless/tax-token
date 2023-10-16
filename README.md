# Foundry template

This is a template for a Foundry project.

## Installation

```
forge init -t lumen-limitless/template-foundry
```

## Local development

This project uses [Foundry](https://github.com/foundry-rs/foundry) as the development framework.

### Dependencies

```
forge install
```

### Compilation

```
forge build
```

### Testing

```
forge test
```

### Contract deployment

Please create a `.env` file before deployment. An example can be found in `.env.example`.

#### Dryrun

```
forge script script/Contract.s.sol -f [network]
```

### Live

```
forge script script/Contract.s.sol -f [network] --verify --broadcast
```
