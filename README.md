# 📹 TRASSIR Monitor / Трассир Монитор

> **Система мониторинга серверов TRASSIR** — веб-дашборд с live-обновлением, алертами, историей, Telegram и Email уведомлениями.

[![Platform](https://img.shields.io/badge/platform-Debian%2F12%2F13-blue)](https://www.debian.org/)
[![Python](https://img.shields.io/badge/python-3.x-blue)](https://www.python.org/)
[![Shell](https://img.shields.io/badge/install-one--liner-green)](#-быстрая-установка)

---

## 🌐 Что это такое?

**TRASSIR Monitor** (Трассир Монитор) — самостоятельно размещаемое веб-приложение для мониторинга серверов видеонаблюдения [TRASSIR](https://www.dssl.ru/).  
Устанавливается одной командой на Debian, не требует ручной настройки Python или Nginx.

### Ключевые слова для поиска
`Трассир Монитор` · `TRASSIR Monitor` · `мониторинг TRASSIR` · `TRASSIR Dashboard` · `трассир алерты` · `видеонаблюдение мониторинг linux` · `trassir telegram уведомления` · `trassir email alert` · `trassir camera offline`

---

## ✨ Возможности

| Функция | Описание |
|---|---|
| 🏠 Live-дашборд | Все серверы на одном экране, автообновление через WebSocket |
| 📷 Имена офлайн-камер | Определяет конкретные названия каналов через API `/objects/` TRASSIR |
| 🔔 Алерты | Диски, CPU, камеры, архив — без дублирования (1 событие = 1 алерт) |
| ✅ Восстановления | Отдельный алерт при возврате в онлайн + расчёт времени простоя |
| 📊 Графики | CPU, камеры, архив за 6 ч / 24 ч / 7 дн |
| 💬 Telegram | Мгновенные уведомления, поддержка HTTP-прокси, несколько получателей |
| 📬 Email | HTML-письма через SMTP (Gmail, Yandex, Mail.ru, корпоративный) |
| ⚙️ Веб-настройки | Управление серверами, SMTP, Telegram — через браузер на `/settings` |
| 🕐 Московское время | Все данные сохраняются в UTC+3 |
| 🗑 Деинсталлятор | Удаляет только проект, системные пакеты не трогает |

---

## 📦 Системные требования

- **ОС:** Debian 11 / 12 / 13
- **Права:** root / sudo
- **Серверы TRASSIR** с включённым веб-сервером и заполненным SDK-паролем
- Свободный порт (по умолчанию `8080`)
- Интернет на время установки

> Python 3, виртуальное окружение, Nginx и все зависимости устанавливаются **автоматически**.

---

## 🚀 Быстрая установка

### 1. Основной монитор

```bash
wget https://raw.githubusercontent.com/naumenis-code/TRASSIR-Monitor/main/install-trassir-monitor.sh
sudo bash install-trassir-monitor.sh
```

Установщик спросит:
- **Порт** веб-интерфейса (по умолчанию `8080`)
- **Интервал опроса** серверов в секундах (по умолчанию `15`)

После установки откройте `http://<IP>:8080` и добавьте первый сервер TRASSIR.

---

### 2. Telegram-уведомления *(опционально)*

```bash
wget https://raw.githubusercontent.com/naumenis-code/TRASSIR-Monitor/main/install-telegram-notifier.sh
sudo bash install-telegram-notifier.sh
```

Потребуется:
- **Токен бота** — получить у [@BotFather](https://t.me/BotFather) командой `/newbot`
- **Chat ID** — узнать через [@userinfobot](https://t.me/userinfobot)
- **HTTP-прокси** — опционально, если Telegram недоступен из сети

---

### 3. Email-уведомления *(опционально)* `v1.3`

```bash
wget https://raw.githubusercontent.com/naumenis-code/TRASSIR-Monitor/main/install-mail-notifier.sh
sudo bash install-mail-notifier.sh
```

Потребуется:
- **SMTP-сервер** (например, `smtp.gmail.com`)
- **Порт**: `587` — STARTTLS, `465` — SSL/TLS
- **Логин и пароль** (для Gmail — [пароль приложения App Password](https://myaccount.google.com/apppasswords))
- **Email получателей** — несколько адресов через запятую

> Все параметры можно изменить позже через `/settings` в браузере.

---

## 🔑 Где взять SDK-пароль TRASSIR

На каждом сервере TRASSIR:  
**Настройки → Веб-сервер → Общие → Пароль SDK**

---

## 🖥 Веб-интерфейс

```
Дашборд:    http://<IP>:8080/
Детали:     http://<IP>:8080/server/<id>
Настройки:  http://<IP>:8080/settings
```

**Дашборд** показывает по каждому серверу: статус · камеры онлайн/всего · CPU · диски · архив · uptime · отклик · счётчик алертов

**Детальная страница** — метрики, интерактивный график, список всех алертов с возможностью сброса.

---

## 🔔 Формат уведомлений

Каждое уведомление (Telegram и Email) содержит:

- 🖥 Название и IP сервера
- ⚠ Описание события (с именами конкретных камер)
- ⏱ Время простоя (для уведомлений о восстановлении)
- 📊 Текущее состояние: CPU%, камеры, архив, uptime, отклик
- 🔗 Прямая ссылка на страницу сервера в мониторе

**Типы алертов:**

| Иконка | Событие |
|---|---|
| ✅ | ВОССТАНОВЛЕНИЕ — камера / сервер вернулся в онлайн + время простоя |
| 📷 | ОТВАЛ КАМЕР — с именами конкретных каналов |
| 🔥 | ВЫСОКАЯ НАГРУЗКА CPU |
| 💾 | ПРОБЛЕМА С АРХИВОМ |
| 💿 | ОШИБКА ДИСКОВ |
| 🔴 | КРИТИЧЕСКИЙ АЛЕРТ |

---

## 📋 Управление сервисами

```bash
# Основной монитор
systemctl status trassir-monitor
systemctl restart trassir-monitor
tail -f /opt/trassir-monitor/logs/system.log

# Telegram-бот
systemctl status trassir-tgbot
systemctl restart trassir-tgbot
tail -f /opt/trassir-monitor/logs/tgbot.log

# Email-демон
systemctl status trassir-mailbot
systemctl restart trassir-mailbot
tail -f /opt/trassir-monitor/logs/mailbot.log
```

---

## 🗑 Удаление

```bash
# Удалить Telegram-бота
sudo bash uninstall-telegram-bot.sh

# Удалить Email-демона
sudo bash uninstall-mail-notifier.sh

# Удалить весь TRASSIR Monitor
sudo trassir-monitor-uninstall
```

Деинсталлятор удаляет **только файлы проекта**. Python, Nginx и системные пакеты сохраняются. База данных сохраняется по запросу.

---

## 📁 Файлы проекта

| Файл | Назначение |
|---|---|
| `install-trassir-monitor.sh` | Основная установка мониторинга |
| `install-telegram-notifier.sh` | Установка Telegram-уведомлений |
| `install-mail-notifier.sh` | Установка Email-уведомлений |
| `uninstall-telegram-bot.sh` | Удаление Telegram-бота |
| `uninstall-mail-notifier.sh` | Удаление Email-демона |

---

## 🛠 Технологии

- **Backend:** Python 3, Flask, Flask-SocketIO, Gunicorn, SQLite
- **Frontend:** Bootstrap 5, Chart.js, WebSocket (Socket.io)
- **Proxy:** Nginx
- **Init:** systemd
- **Уведомления:** smtplib (Email), requests → Telegram Bot API

---

## ❓ Частые вопросы

**Почему имена камер не видны сразу?**  
Имена запрашиваются только при наличии офлайн-камер. Для большого количества каналов запрос идёт последовательно и занимает несколько секунд.

**Как изменить порт после установки?**  
Отредактируйте `/etc/nginx/sites-available/trassir-monitor`, замените `listen <порт>`, затем `systemctl reload nginx`.

**Можно ли без SSL?**  
Да — при добавлении сервера снимите галочку «Использовать SSL».

**Gmail не отправляет письма?**  
Нужен [пароль приложения (App Password)](https://myaccount.google.com/apppasswords), не основной пароль аккаунта.

---

<div align="center">

**Сделано для администраторов систем видеонаблюдения TRASSIR**  
Вопросы и предложения — через [Issues](https://github.com/naumenis-code/TRASSIR-Monitor/issues)

</div>
