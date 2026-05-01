# 📹 TRASSIR Monitor / Трассир Монитор

> **Система мониторинга серверов TRASSIR** — веб-дашборд с алертами, историей и уведомлениями в Telegram и Email.

[![Platform](https://img.shields.io/badge/platform-Debian%2011%2F12%2F13-blue)](https://www.debian.org/)
[![Python](https://img.shields.io/badge/python-3.x-blue)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 🌐 Что такое TRASSIR Monitor?

**TRASSIR Monitor** (Трассир Монитор) — это самостоятельно размещаемое веб-приложение для мониторинга серверов видеонаблюдения [TRASSIR](https://www.dssl.ru/).  
Устанавливается на Linux-сервер одной командой и даёт вам:

- 🖥 **Live-дашборд** с автообновлением состояния всех серверов
- 📷 **Имена конкретных отключённых камер** — не просто «5 камер офлайн», а «#12 Вход, #34 Парковка…»
- 🔔 **Алерты** при проблемах: диски, CPU, архив, камеры
- 📊 **Графики** CPU / камер / архива за 6 часов, 24 часа, 7 дней
- 📬 **Email-уведомления** (опционально) через любой SMTP
- 💬 **Telegram-уведомления** (опционально) с поддержкой HTTP-прокси
- ✅ **Уведомления о восстановлении** — когда камера или сервер снова в онлайне, с указанием времени простоя

---

## 🔍 Поиск / Keywords

`Трассир Монитор` · `TRASSIR Monitor` · `мониторинг TRASSIR` · `TRASSIR Dashboard` · `видеонаблюдение мониторинг` · `trassir alert` · `trassir telegram` · `trassir email notification`

---

## ✨ Возможности

| Функция | Описание |
|---|---|
| 🏠 Live-дашборд | Все серверы на одном экране, данные обновляются через WebSocket |
| 📷 Имена камер | Определяет названия офлайн-каналов через API `/objects/` TRASSIR |
| 📊 История | Графики CPU, камер и архива за выбранный период |
| 🔔 Алерты | Критические и предупреждающие события с дедупликацией |
| ✅ Восстановления | Отдельные алерты при возврате в онлайн + расчёт времени простоя |
| 📬 Email | Красивые HTML-письма через SMTP (Gmail, Yandex, Mail.ru, корпоративный) |
| 💬 Telegram | Мгновенные уведомления, поддержка HTTP-прокси |
| ⚙️ Веб-настройки | Управление серверами, SMTP, Telegram — всё через браузер |
| 🕐 Московское время | Все данные в UTC+3 |
| 🗑 Деинсталлятор | Удаление только проекта, системные пакеты не затрагиваются |

---

## 🖼 Интерфейс

```
Дашборд:     http://<IP>:8080/
Детали:      http://<IP>:8080/server/<id>
Настройки:   http://<IP>:8080/settings
```

---

## 📦 Системные требования

- **ОС:** Debian 11 / 12 / 13
- **Python:** 3.x (устанавливается автоматически)
- **Nginx:** устанавливается автоматически
- **Доступ:** root (sudo)
- **Порт:** 8080 (по умолчанию, можно изменить)

---

## 🚀 Установка

### 1. Основной монитор

```bash
wget https://raw.githubusercontent.com/naumenis-code/TRASSIR-Monitor/main/install-trassir-monitor.sh
sudo bash install-trassir-monitor.sh
```

Установщик спросит:
- **Порт** веб-интерфейса (по умолчанию `8080`)
- **Интервал опроса** серверов TRASSIR в секундах (по умолчанию `15`)

После завершения откройте `http://<IP-сервера>:8080` и добавьте первый сервер TRASSIR.

---

### 2. Telegram-уведомления (опционально)

```bash
wget https://raw.githubusercontent.com/naumenis-code/TRASSIR-Monitor/main/install-telegram-notifier.sh
sudo bash install-telegram-notifier.sh
```

Что понадобится:
- **Токен бота** — получить у [@BotFather](https://t.me/BotFather) командой `/newbot`
- **Chat ID** — узнать через [@userinfobot](https://t.me/userinfobot)
- **HTTP-прокси** — опционально, если Telegram заблокирован

---

### 3. Email-уведомления (опционально)

```bash
wget https://raw.githubusercontent.com/naumenis-code/TRASSIR-Monitor/main/install-mail-notifier.sh
sudo bash install-mail-notifier.sh
```

Что понадобится:
- **SMTP-сервер** (например, `smtp.gmail.com`)
- **Порт** (587 для STARTTLS, 465 для SSL)
- **Логин и пароль** (для Gmail — [пароль приложения](https://myaccount.google.com/apppasswords))
- **Email получателей** — можно несколько через запятую

> Все параметры можно изменить позже через веб-интерфейс `/settings`.

---

## 🔑 Где взять SDK-пароль TRASSIR

На сервере TRASSIR:  
**Настройки → Веб-сервер → Общие → Пароль SDK**

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

## 🔔 Формат уведомлений

Каждое уведомление (Telegram и Email) содержит:

| Поле | Описание |
|---|---|
| 🖥 Сервер | Название и IP |
| ⚠ Событие | Описание проблемы или восстановления |
| 📷 Камеры офлайн | С именами конкретных каналов |
| ⏱ Время простоя | Для уведомлений о восстановлении |
| 📊 Состояние | CPU%, камеры онлайн, архив, uptime, отклик |
| 🔗 Ссылка | Прямая ссылка в веб-интерфейс монитора |

**Типы алертов:**
- ✅ ВОССТАНОВЛЕНИЕ — камера или сервер вернулся в онлайн (+ время простоя)
- 📷 ОТВАЛ КАМЕР — с именами каналов
- 🔥 ВЫСОКАЯ НАГРУЗКА CPU
- 💾 ПРОБЛЕМА С АРХИВОМ
- 💿 ОШИБКА ДИСКОВ
- 🔴 КРИТИЧЕСКИЙ АЛЕРТ

---

## 🗑 Удаление

### Удалить только Telegram-бота

```bash
sudo bash uninstall-telegram-notifier.sh
```

### Удалить только Email-демона

```bash
sudo bash uninstall-mail-notifier.sh
```

### Удалить весь TRASSIR Monitor

```bash
sudo trassir-monitor-uninstall
```

> Деинсталлятор удаляет **только файлы проекта**. Python, Nginx и системные пакеты не затрагиваются. При желании данные (БД и логи) можно сохранить перед удалением.

---

## 📁 Структура установки

```
/opt/trassir-monitor/
├── app/
│   ├── app.py           # Основное Flask-приложение
│   ├── tg_bot.py        # Telegram-демон (опционально)
│   └── mail_bot.py      # Email-демон (опционально)
├── templates/           # HTML-шаблоны
├── static/              # Статические файлы
├── data/
│   └── trassir.db       # SQLite-база данных
├── logs/                # Логи
├── backups/             # Автоматические бэкапы перед обновлениями
├── venv/                # Python виртуальное окружение
├── config.ini           # Telegram-токен и прокси
└── gunicorn_config.py   # Конфигурация Gunicorn
```

---

## 🛠 Технологии

- **Backend:** Python 3, Flask, Flask-SocketIO, Gunicorn, SQLite
- **Frontend:** Bootstrap 5, Chart.js, WebSocket (Socket.io)
- **Proxy:** Nginx
- **Init:** systemd
- **Уведомления:** smtplib (Email), requests → Telegram Bot API

---

## 🤝 Совместимость с TRASSIR

Монитор использует стандартное HTTP API TRASSIR:
- `/health` — общее состояние сервера
- `/objects/` — список всех объектов (каналов)
- `/objects/<GUID>` — состояние конкретного канала

Поддерживается как HTTP, так и HTTPS (SSL) подключение.

---

## 📝 Лицензия

MIT License — свободное использование, модификация и распространение.

---

<div align="center">

**Сделано для администраторов систем видеонаблюдения TRASSIR**  
Вопросы и предложения — через [Issues](https://github.com/naumenis-code/TRASSIR-Monitor/issues)

</div>
