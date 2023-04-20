# juice-contract-template
Template used to code juicy solidity stuff - includes forge, libs, etc

Install dependencies (forge tests, Juice-contracts-V3, OZ) via `forge install && yarn install`

Use this template as a starting point, do not push straight on main, rather create a new branch and open a PR - your reviewer will love you for this.

# Usage
use `yarn test` to run tests

use `yarn test:fork` to run tests in CI mode (including slower mainnet fork tests)

<br>

use `yarn size` to check contract size

use `yarn doc` to generate natspec docs

use `yarn lint` to lint the code

use `yarn tree` to generate a Solidity dependency tree

<br>

use `yarn deploy:mainnet` and `yarn deploy:goerli` to deploy and verify (see .env.example for required env vars, using a ledger by default).

## Code coverage
Run `yarn coverage`to display code coverage summary and generate an LCOV report

To display code coverage in VSCode:
- You need to install the [coverage gutters extension (Ryan Luker)](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) or any other extension handling LCOV reports
- ctrl shift p > "Coverage Gutters: Display Coverage" (coverage are the colored markdown lines in the left gutter, after the line numbers)

## PR
Github CI flow will run both unit and forked tests, log the contracts size (with the tests) and check linting compliance.