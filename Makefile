# Use Pixi-managed tasks inside the halligan project
.PHONY: install format lint typecheck test precommit up down models

install:
	pixi -p ./halligan install

format:
	pixi -p ./halligan run format

lint:
	pixi -p ./halligan run lint

typecheck:
	pixi -p ./halligan run typecheck

test:
	pixi -p ./halligan run test

precommit:
	pixi -p ./halligan run precommit

up:
	docker compose up -d --build

down:
	docker compose down -v

models:
	bash ./halligan/get_models.sh
