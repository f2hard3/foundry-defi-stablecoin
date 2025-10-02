# Foundry DeFi Stablecoin

A decentralized stablecoin protocol built with [Foundry](https://github.com/foundry-rs/foundry), featuring robust testing, modular contracts, and Chainlink integration.

## Project Structure

```
.
├── src/                # Main Solidity contracts
├── script/             # Deployment and helper scripts
├── test/               # Test suite (unit, fuzz, mocks)
├── lib/                # External dependencies (OpenZeppelin, Chainlink, forge-std)
├── foundry.toml        # Foundry configuration
└── README.md           # Project documentation
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (optional, for dependency management)

### Installation

Clone the repository and install dependencies:

```sh
git clone <your-repo-url>
cd foundry-defi-stablecoin
forge install
```

### Build

```sh
forge build
```

### Test

```sh
forge test -vvv
```

### Directory Details

- **src/**: Core smart contracts for the stablecoin and engine logic.
- **script/**: Deployment and configuration scripts.
- **test/**: Comprehensive tests, including unit, fuzz, and mock tests.
- **lib/**: External libraries (OpenZeppelin, Chainlink, forge-std).

### Remappings

Remappings are set in `foundry.toml` for OpenZeppelin and Chainlink contracts:

```toml
remappings = [
    "@openzeppelin/contracts=lib/openzeppelin-contracts/contracts",
    "@chainlink/contracts=lib/chainlink-brownie-contracts/contracts",
]
```

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License

[MIT](LICENSE)

---

_Built with [Foundry](https://github.com/foundry-rs/foundry) and inspired by modern DeFi best practices._
