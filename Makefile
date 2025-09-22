install:
	poetry install
	forge install
	yarn

fmt:
	forge fmt
	forge fmt --check

lint:
	yarn run solhint \
		--config .solhint.json \
		--quiet \
		--noPrompt \
		contracts/**/*.sol

build:
	forge build

tests:
	forge test -vvv

tests-coverage:
	forge coverage -vvvv

tests-hardhat:
	yarn test:hardhat

ci:
	act

docs:
	cd doc && poetry run python generate_pdf.py

all: fmt lint build tests
