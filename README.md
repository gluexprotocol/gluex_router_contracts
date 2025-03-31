# GlueX Router Contracts
Welcome to the **GlueX Router Contracts** public repository!  
This repository serves as a **central hub for all versions of the GlueX Router smart contracts**. Each version is organized into its own directory, offering clear modularity, versioning, and history tracking for ongoing development and upgrades.

---

## 📁 Repository Structure
Each folder in the root directory represents a specific **version** of the router contracts. Inside each version folder, you will find:

- `Executor.sol`: Designed to execute multiple smart contract interactions in a single transaction.
- `Router.sol`: Modular smart contract that facilitates user to perform complex, multi-step interactions atomically.

```bash
├── router_v1/
│   ├── base/
│   │   └── RouterStructs.sol
│   ├── interfaces/
│   │   └── IDaiLikePermit.sol
│   │   └── IERC20.sol
│   │   └── IERC20Permit.sol
│   │   └── IExecutor.sol
│   │   └── IPermit2.sol
│   │   └── IWrappedNativeToken.sol
│   ├── lib/
│   │   └── RevertReasonForwarder.sol
│   │   └── SafeERC20.sol
│   ├── utils/
│   │   └── EthReceiver.sol
│   ├── Executor.sol
│   └── Router.sol
...
```

---

## 🛠 Getting Started
To get started with this repository:

1. Clone the repo:
```bash
git clone https://github.com/gluexprotocol/gluex_router_contracts.git
cd gluex_router_contracts
```

2. Explore the codebase:
Start with router_v1/ Router.sol and Executor.sol to understand the base implementation.

---

## 🧑‍💻 Contributing
We welcome community contributions! Follow the guidelines below to make the PR process smooth and effective.

### ✅ How to Contribute
1. Fork the repository.
2. Create a new branch for your changes
3. Target one issue per PR.
    * Avoid combining fixes or features for multiple issues in a single pull request.
4. Include a summary of the change in the PR description:
    * What does it fix or add?
    * Link to the issue number.
5. Add screenshots or code snippets as needed.
    * Visual clarity helps reviewers understand your intent faster.

---

## 📌 Issues
1. Create an issue before submitting a PR unless it's a trivial fix.
2. Be descriptive:
    * What’s the problem?
    * Steps to reproduce?
    * Expected vs actual?
    * Add relevant labels (bug, feature, enhancement) if possible.

---

## 🚨 Code Standards
* Follow Solidity best practices and the project’s style guidelines.
* Keep contracts modular and well-documented.
* Use comments and NatSpec annotations where helpful.