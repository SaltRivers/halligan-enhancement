# Use Pixi-managed tasks inside the halligan project
.PHONY: install format lint typecheck test precommit up down models

install:
	pixi install -p ./halligan

format:
	pixi run -p ./halligan format

lint:
	pixi run -p ./halligan lint

typecheck:
	pixi run -p ./halligan typecheck

test:
	pixi run -p ./halligan test

precommit:
	pixi run -p ./halligan precommit

up:
	docker compose up -d --build

down:
	docker compose down -v

models:
	bash ./halligan/get_models.sh
