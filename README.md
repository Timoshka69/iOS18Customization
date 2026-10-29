<p align="center">
  <img src="assets/banner.png" alt="iOS18Customization" width="100%">
</p>

<h1 align="center">iOS18Customization</h1>

<p align="center">
  The iOS 18 home screen on iOS 15.<br>
  Dark and tinted icons and widgets, large icons, and the iOS 18 customize menu.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-15.0%20–%2015.8.x-7B5CFF">
  <img src="https://img.shields.io/badge/jailbreak-rootless%20%7C%20rootful-7B5CFF">
  <img src="https://img.shields.io/badge/arch-arm64%20%7C%20arm64e-lightgrey">
  <img src="https://github.com/Timoshka69/iOS18Customization/actions/workflows/main.yml/badge.svg">
</p>

---

## Features

- **Light, Dark, Auto and Tinted** icons — like iOS 18
- Tinted **widgets** and notification badges
- **Small / Large** icons (large ones without labels, widgets grow a little too)
- Color sliders and an **eyedropper** that picks a color from your wallpaper
- Wallpaper dimming
- A **settings page** in the Settings app with switches: Tint Icons, Tint Widgets, Tint Icons in Settings

## How to use

1. Long-press an empty spot on the home screen.
2. Tap the **+** in the top left corner → **Customize**.
3. Pick a look. Everything changes instantly, no respring.

The switches live in **Settings → iOS18Customization**.

## Install

Download the `.deb` from [Releases](https://github.com/Timoshka69/iOS18Customization/releases) (or **Actions → latest build → Artifacts**):

- `..._rootless_iphoneos-arm64.deb` — Dopamine, palera1n rootless
- `..._rootful_iphoneos-arm.deb` — rootful jailbreaks

Open it in Sileo, Zebra or Filza and install. Needs iOS 15.0 – 15.8.x, ElleKit / Substitute and PreferenceLoader.

## Build

Push to GitHub — the workflow in [`.github/workflows/main.yml`](.github/workflows/main.yml) builds both packages.
Locally with Theos:

```bash
make package FINALPACKAGE=1                            # rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME= # rootful
```

## Optional: dark icon pack

The tweak makes dark and tinted icons by itself. If you have hand-made dark icons (Homescreen18 / SnowBoard style,
`<bundle id>.png`), put them in `/var/jb/Library/Application Support/iOS18Customization/IconBundles/` and respring.
The tweak ships no icons of its own — they belong to Apple and the app developers.

## Credits

Inspired by [Homescreen18](https://t.me/evgeniy558) for iOS 16–17. Built with [Theos](https://theos.dev). MIT license.

---

## По-русски

Домашний экран из iOS 18 на iOS 15: тёмные и цветные иконки и виджеты, крупные иконки без подписей, меню «Настроить» как в iOS 18.

- Зажми пустое место на рабочем столе → нажми **+** слева вверху → **Настроить**.
- Переключатели «Окрашивать иконки», «Окрашивать виджеты», «Окрашивать в Настройках» — в приложении **Настройки → iOS18Customization**.
- Установка: `.deb` из Releases или Actions (`rootless` — для Dopamine), открыть в Sileo / Filza.
