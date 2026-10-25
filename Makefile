.PHONY: all build run app icon test clean

all: build

## 编译（debug）
build:
	swift build

## 跑起来
run:
	swift run

## 打包成 dist/深大电量.app
app:
	./scripts/build-app.sh

## 只重新生成图标
icon:
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

## 命令行查一次（示例）
test:
	swift build -c release
	.build/release/SZUPower --query 南校区 冬筑3-6楼 301

clean:
	rm -rf .build build dist
