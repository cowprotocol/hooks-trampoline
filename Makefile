include .env
export $(shell sed 's/=.*//' .env)

.PHONY: deploy
deploy:
	forge script script/DeployHooksTrampoline.s.sol -vvvv --broadcast --rpc-url "${ETH_RPC_URL}" --verify
