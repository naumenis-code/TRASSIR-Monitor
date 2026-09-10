#!/bin/bash
# ============================================
# TRASSIR Monitor v13.0
# Проверено на Debian 12 13
# ============================================
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Пути
INSTALL_DIR="/opt/trassir-monitor"
SERVICE="trassir-monitor"

# Очистка экрана
clear

# Баннер
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   TRASSIR Monitor v13.0 — Final Complete     ║${NC}"
echo -e "${GREEN}║   Имена каналов • Алерты • Live дашборд      ║${NC}"
echo -e "${GREEN}║   Debian 12/13 • gevent • Python 3.12/3.13   ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Определяем версию Debian и Python для информации
DEBIAN_VERSION=$(. /etc/os-release && echo "$VERSION_ID")
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
echo -e "${CYAN}  ОС: Debian ${DEBIAN_VERSION}  |  Python: ${PYTHON_VERSION}${NC}"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root:${NC}"
    echo -e "   ${YELLOW}sudo bash install.sh${NC}"
    exit 1
fi

# ============================================
# СВЕЖАЯ УСТАНОВКА ИЛИ ОБНОВЛЕНИЕ?
# ============================================
# Единственный надёжный признак существующей установки — сама база
# данных, а не отдельный флаг/маркер, который может разойтись с
# реальностью. Раньше повторный запуск этого скрипта БЕЗУСЛОВНО удалял
# $INSTALL_DIR (см. ШАГ 1 ниже) — то есть любая "переустановка ради
# обновления кода" молча уничтожала всю БД (серверы, историю, алерты,
# пароль администратора) без единого предупреждения. Теперь наличие
# $INSTALL_DIR/data/trassir.db переключает скрипт в режим обновления:
# порт и пароль не переспрашиваются, данные сохраняются вокруг ШАГа 1.
IS_UPDATE=0
META_FILE="$INSTALL_DIR/data/.install_meta"
if [ -f "$INSTALL_DIR/data/trassir.db" ]; then
    IS_UPDATE=1
fi

if [ "$IS_UPDATE" -eq 1 ]; then
    echo -e "${CYAN}Обнаружена существующая установка в $INSTALL_DIR${NC}"
    echo -e "${CYAN}Режим ОБНОВЛЕНИЯ: код/шаблоны/сервисы будут пересозданы,${NC}"
    echo -e "${CYAN}база данных, порт и пароль администратора — сохранены.${NC}"
    echo ""

    # Порт восстанавливаем в три попытки, от самой надёжной к самой
    # рискованной — раньше при отсутствующем метафайле молча
    # подставлялся хардкод 8080, и сообщение при этом всё равно
    # утверждало "сохранён с прошлой установки", хотя это было просто
    # предположение. На установке со "старой версией" (а метафайл
    # появился только в этой правке — то есть ЛЮБАЯ по-настоящему старая
    # установка от него ничего не получит) это могло молча переключить
    # nginx на не тот порт, ничего не спросив и не предупредив — ровно
    # то, что заставило перепроверять эту логику ещё раз.
    WEB_PORT=""
    PORT_SOURCE=""

    # 1) Метафайл (см. ШАГ 3) — самый надёжный источник, если установка
    #    уже проходила через эту же версию скрипта хотя бы раз.
    if [ -f "$META_FILE" ]; then
        # shellcheck disable=SC1090
        source "$META_FILE"
        if [ -n "$WEB_PORT" ]; then
            PORT_SOURCE="из файла метаданных"
        fi
    fi

    # 2) Живой конфиг nginx ещё не удалён (удаление — только в ШАГе 1
    #    ниже) — реальный порт всегда лежит в его же собственной строке
    #    "listen $WEB_PORT default_server;" (см. генерацию конфига
    #    дальше по этому же скрипту), независимо от того, какая версия
    #    установщика его когда-то написала. Это единственный источник,
    #    который переживёт даже установку, сделанную до появления самого
    #    понятия метафайла.
    if [ -z "$WEB_PORT" ] && [ -f /etc/nginx/sites-available/trassir-monitor ]; then
        DETECTED_PORT=$(grep -oP 'listen\s+\K[0-9]+(?=\s+default_server)' \
            /etc/nginx/sites-available/trassir-monitor 2>/dev/null | head -1)
        if [ -n "$DETECTED_PORT" ]; then
            WEB_PORT="$DETECTED_PORT"
            PORT_SOURCE="определён по действующему конфигу nginx"
        fi
    fi

    # 3) Ни то, ни другое не сработало — не гадаем молча: спрашиваем
    #    явно, с честным предупреждением, почему это вообще происходит
    #    на "обновлении", где остальные вопросы пропущены.
    if [ -z "$WEB_PORT" ]; then
        echo -e "  ${YELLOW}⚠ Не удалось определить порт предыдущей установки автоматически${NC}"
        echo -e "  ${YELLOW}(ни файла метаданных, ни рабочего конфига nginx не нашлось).${NC}"
        read -p "  Порт веб-интерфейса (Enter для 8080): " WEB_PORT
        WEB_PORT=${WEB_PORT:-8080}
        PORT_SOURCE="введён вручную — автоопределение не сработало"
    fi

    APP_PORT=$((WEB_PORT + 1))
    while ss -tlnp 2>/dev/null | grep -q ":${APP_PORT} "; do
        APP_PORT=$((APP_PORT + 1))
    done
    echo -e "  ${CYAN}Порт веб-интерфейса: ${WEB_PORT} (${PORT_SOURCE})${NC}"
    echo -e "  ${CYAN}Внутренний порт приложения: ${APP_PORT}${NC}"
    echo ""
else
    # ============================================
    # ЗАПРОС ПАРАМЕТРОВ У ПОЛЬЗОВАТЕЛЯ
    # ============================================
    echo -e "${YELLOW}Настройка параметров установки:${NC}"
    echo ""

    echo -e "  ${BOLD}Порт Web-интерфейса${NC}"
    echo -e "  На каком порту будет доступен веб-интерфейс мониторинга"
    read -p "  Порт (Enter для 8080): " WEB_PORT
    WEB_PORT=${WEB_PORT:-8080}

    # Проверяем что внешний порт не занят
    if ss -tlnp 2>/dev/null | grep -q ":${WEB_PORT} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${WEB_PORT} "; then
        echo -e "  ${YELLOW}⚠ Порт ${WEB_PORT} уже используется другим процессом!${NC}"
        echo -e "  Проверьте: ${CYAN}ss -tlnp | grep :${WEB_PORT}${NC}"
        read -p "  Продолжить установку? (y/N): " cont
        [[ $cont =~ ^[Yy]$ ]] || exit 1
    fi

    # Вычисляем внутренний порт gunicorn — WEB_PORT+1, ищем первый свободный
    APP_PORT=$((WEB_PORT + 1))
    while ss -tlnp 2>/dev/null | grep -q ":${APP_PORT} "; do
        APP_PORT=$((APP_PORT + 1))
    done
    echo -e "  ${CYAN}Внутренний порт приложения: ${APP_PORT}${NC}"
    echo ""

    echo -e "  ${BOLD}Интервал опроса TRASSIR${NC}"
    echo -e "  Как часто (в секундах) опрашивать серверы TRASSIR"
    echo -e "  Рекомендуется: 15 секунд"
    read -p "  Интервал (Enter для 15): " POLL
    POLL=${POLL:-15}
    if ! [[ "$POLL" =~ ^[0-9]+$ ]] || [ "$POLL" -lt 1 ]; then
        echo -e "  ${YELLOW}Некорректное значение, использую 15 секунд${NC}"
        POLL=15
    fi
    echo ""

    echo -e "  ${BOLD}Пароль администратора${NC}"
    echo -e "  Без входа дашборд можно только просматривать — добавление и"
    echo -e "  удаление серверов, изменение настроек требуют этот пароль."
    echo -e "  Позже сменить прямо на сервере: ${CYAN}sudo trassir-monitor-set-password${NC}"
    echo ""
    while true; do
        read -p "  Пароль (Enter — сгенерировать случайный): " ADMIN_PASSWORD
        if [ -z "$ADMIN_PASSWORD" ]; then
            ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
            echo -e "  ${GREEN}✓${NC} Сгенерирован пароль: ${BOLD}${ADMIN_PASSWORD}${NC}"
            echo -e "  ${RED}Запишите его сейчас — второй раз он нигде не покажется.${NC}"
            break
        fi
        if [ ${#ADMIN_PASSWORD} -lt 4 ]; then
            echo -e "  ${YELLOW}Слишком короткий пароль (минимум 4 символа), попробуйте снова${NC}"
            continue
        fi
        read -p "  Повторите пароль: " ADMIN_PASSWORD_CONFIRM
        if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
            echo -e "  ${RED}Пароли не совпадают, попробуйте снова${NC}"
            continue
        fi
        echo -e "  ${GREEN}✓${NC} Пароль принят"
        break
    done
    echo ""

    echo -e "${GREEN}✅ Параметры установки:${NC}"
    echo -e "   • Порт Web-интерфейса: ${BOLD}$WEB_PORT${NC}"
    echo -e "   • Интервал опроса: ${BOLD}${POLL} секунд${NC}"
    echo -e "   • Пароль администратора: ${BOLD}задан${NC}"
    echo -e "   • Каталог установки: ${BOLD}$INSTALL_DIR${NC}"
    echo ""
fi

# ============================================
# ШАГ 1: ОЧИСТКА СТАРОЙ УСТАНОВКИ
# ============================================
echo -e "${YELLOW}[1/7] Очистка старой установки...${NC}"
echo ""

# Останавливаем сервис если он запущен
if systemctl is-active --quiet $SERVICE 2>/dev/null; then
    echo "  • Остановка сервиса $SERVICE..."
    systemctl stop $SERVICE
    echo "    ✓ Сервис остановлен"
fi

# Отключаем автозапуск
if systemctl is-enabled --quiet $SERVICE 2>/dev/null; then
    echo "  • Отключение автозапуска..."
    systemctl disable $SERVICE
    echo "    ✓ Автозапуск отключён"
fi

# При обновлении сохраняем data/ (БД со всей историей, серверами,
# алертами и хешем пароля администратора) во временный каталог ВНЕ
# $INSTALL_DIR перед его удалением ниже — восстанавливается обратно в
# ШАГе 3, сразу после того как каталог data/ будет создан заново.
#
# static/ (bootstrap/chart.js/socket.io/иконки, см. ШАГ 5) сохраняем
# туда же и по той же причине, но не ради данных, а ради автономности:
# эти файлы качаются с CDN один раз при самой первой установке, а
# дальше должны просто оставаться на диске — на обновлении сети может
# уже не быть вообще (сеть, для которой это всё и делается), и без
# этой сохранёнки ШАГ 5 остался бы без единого рабочего пакета после
# `rm -rf $INSTALL_DIR`, потому что качать их заново было бы неоткуда.
DATA_PRESERVE_DIR=""
if [ "$IS_UPDATE" -eq 1 ] && [ -d "$INSTALL_DIR/data" ]; then
    echo "  • Сохранение базы данных и статических файлов перед обновлением..."
    DATA_PRESERVE_DIR=$(mktemp -d)
    cp -a "$INSTALL_DIR/data" "$DATA_PRESERVE_DIR/data"
    if [ -d "$INSTALL_DIR/static" ]; then
        cp -a "$INSTALL_DIR/static" "$DATA_PRESERVE_DIR/static"
    fi
    echo "    ✓ data/ и static/ сохранены во временный каталог"
fi

# Удаляем старый каталог
if [ -d "$INSTALL_DIR" ]; then
    echo "  • Удаление старого каталога $INSTALL_DIR..."
    rm -rf $INSTALL_DIR
    echo "    ✓ Каталог удалён"
fi

# Удаляем старые конфиги
echo "  • Удаление старых конфигурационных файлов..."
rm -f /etc/systemd/system/$SERVICE.service
rm -f /etc/nginx/sites-available/trassir-monitor
rm -f /etc/nginx/sites-enabled/trassir-monitor
rm -f /usr/local/bin/trassir-monitor-uninstall
echo "    ✓ Конфиги удалены"

# Перезагружаем systemd
systemctl daemon-reload
echo "  • systemd перезагружен"

echo ""
echo -e "${GREEN}✅ Очистка завершена${NC}"
echo ""

# ============================================
# ШАГ 2: УСТАНОВКА СИСТЕМНЫХ ПАКЕТОВ
# ============================================
echo -e "${YELLOW}[2/7] Установка системных пакетов...${NC}"
echo ""

# Обновляем список пакетов
echo "  • Обновление списка пакетов..."
apt-get update -qq
echo "    ✓ Список пакетов обновлён"

echo ""
echo "  • Проверка и установка необходимых пакетов:"

# Список пакетов с описанием
declare -A PKGS
PKGS["python3"]="Интерпретатор Python 3"
PKGS["python3-venv"]="Виртуальное окружение Python"
PKGS["python3-dev"]="Заголовочные файлы Python"
PKGS["gcc"]="Компилятор C (нужен для gevent)"
PKGS["libffi-dev"]="Библиотека FFI (нужна для gevent)"
PKGS["nginx"]="Веб-сервер Nginx"
PKGS["sqlite3"]="База данных SQLite"
PKGS["curl"]="Утилита для HTTP-запросов"
PKGS["wget"]="Утилита для скачивания файлов"
PKGS["net-tools"]="Сетевые утилиты"

# python3-pip: есть в Debian 12, удалён в Debian 13 (там pip только через venv/ensurepip)
if apt-cache show python3-pip &>/dev/null; then
    PKGS["python3-pip"]="Менеджер пакетов Python"
fi

for pkg in "${!PKGS[@]}"; do
    if dpkg -l | grep -q "^ii.*$pkg "; then
        echo "    ✓ $pkg — уже установлен"
    else
        echo "    • $pkg — установка..."
        apt-get install -y $pkg 2>/dev/null
        echo "      ✓ $pkg установлен"
    fi
done

echo ""
echo -e "${GREEN}✅ Системные пакеты готовы${NC}"
echo ""

# ============================================
# ШАГ 3: СОЗДАНИЕ PYTHON ОКРУЖЕНИЯ
# ============================================
echo -e "${YELLOW}[3/7] Создание Python виртуального окружения...${NC}"
echo ""

# Создаём структуру каталогов
echo "  • Создание структуры каталогов..."
mkdir -p $INSTALL_DIR/app
mkdir -p $INSTALL_DIR/templates
mkdir -p $INSTALL_DIR/static
mkdir -p $INSTALL_DIR/data
mkdir -p $INSTALL_DIR/logs
echo "    ✓ Каталоги созданы"

# Восстанавливаем БД и статические файлы, сохранённые в ШАГе 1 перед
# удалением старого каталога (только при обновлении — DATA_PRESERVE_DIR
# пуст на свежей установке). static/ восстанавливаем ДО скачивания
# ресурсов в ШАГе 5 — _dl() там пропускает файл, если он уже на месте,
# так что автономная сеть без интернета на обновлении не остаётся без
# уже однажды скачанных bootstrap/chart.js/socket.io/иконок.
if [ -n "$DATA_PRESERVE_DIR" ] && [ -d "$DATA_PRESERVE_DIR/data" ]; then
    echo "  • Восстановление сохранённой базы данных..."
    rm -rf "$INSTALL_DIR/data"
    cp -a "$DATA_PRESERVE_DIR/data" "$INSTALL_DIR/data"
    echo "    ✓ data/ восстановлен ($(du -sh "$INSTALL_DIR/data" 2>/dev/null | cut -f1))"
fi
if [ -n "$DATA_PRESERVE_DIR" ] && [ -d "$DATA_PRESERVE_DIR/static" ]; then
    echo "  • Восстановление сохранённых статических файлов..."
    rm -rf "$INSTALL_DIR/static"
    cp -a "$DATA_PRESERVE_DIR/static" "$INSTALL_DIR/static"
    echo "    ✓ static/ восстановлен ($(du -sh "$INSTALL_DIR/static" 2>/dev/null | cut -f1))"
fi
rm -rf "$DATA_PRESERVE_DIR" 2>/dev/null || true

# Метаданные установки — на сегодня только порт, единственное, что
# нужно молча восстановить на будущем обновлении вместо повторного
# вопроса пользователю (см. "СВЕЖАЯ УСТАНОВКА ИЛИ ОБНОВЛЕНИЕ?" выше).
# Живёт внутри data/, поэтому переживает и обновление (сохраняется
# вместе с БД), и любые операции, кроме полного uninstall.
cat > $INSTALL_DIR/data/.install_meta << METAEOF
WEB_PORT=$WEB_PORT
METAEOF

# Права на data/ сразу — 775 чтобы www-data мог создавать WAL/SHM файлы SQLite
chown -R www-data:www-data $INSTALL_DIR/data
chmod 775 $INSTALL_DIR/data
echo "    ✓ Права на data/ установлены (775, www-data)"

# Создаём виртуальное окружение
echo ""
echo "  • Создание виртуального окружения Python..."
# --upgrade-deps обновляет pip/setuptools внутри venv (важно для Debian 13)
python3 -m venv --upgrade-deps $INSTALL_DIR/venv 2>/dev/null || \
    python3 -m venv $INSTALL_DIR/venv
echo "    ✓ Виртуальное окружение создано"

# Активируем окружение
echo ""
echo "  • Активация окружения и установка пакетов..."
source $INSTALL_DIR/venv/bin/activate

# Обновляем pip
echo "    • Обновление pip..."
pip install --index-url https://pypi.org/simple/ --timeout=600 --upgrade pip setuptools wheel -q 2>/dev/null || {
    echo "      ⚠ Первая попытка не удалась, пробуем ещё раз..."
    pip install --index-url https://pypi.org/simple/ --timeout=900 --upgrade pip setuptools wheel
}
echo "      ✓ pip обновлён"

# Устанавливаем Flask
echo "    • Установка Flask..."
pip install --index-url https://pypi.org/simple/ --timeout=600 flask -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 flask
echo "      ✓ Flask установлен"

# Устанавливаем Flask-CORS
echo "    • Установка Flask-CORS..."
pip install --index-url https://pypi.org/simple/ --timeout=600 flask-cors -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 flask-cors
echo "      ✓ Flask-CORS установлен"

# Устанавливаем Flask-SocketIO
echo "    • Установка Flask-SocketIO..."
pip install --index-url https://pypi.org/simple/ --timeout=600 flask-socketio -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 flask-socketio
echo "      ✓ Flask-SocketIO установлен"

# Устанавливаем requests
echo "    • Установка requests..."
pip install --index-url https://pypi.org/simple/ --timeout=600 requests -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 requests
echo "      ✓ requests установлен"

# Устанавливаем PySocks — без него requests не умеет схему socks5://
# в параметре proxies (тихо падает с MissingSchema/ошибкой прокси).
# Нужен для SOCKS5-варианта отправки в Telegram-боте (тот же venv).
echo "    • Установка PySocks (поддержка SOCKS5 для requests)..."
pip install --index-url https://pypi.org/simple/ --timeout=600 PySocks -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 PySocks
echo "      ✓ PySocks установлен"

# Устанавливаем schedule
echo "    • Установка schedule..."
pip install --index-url https://pypi.org/simple/ --timeout=600 schedule -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 schedule
echo "      ✓ schedule установлен"

# Устанавливаем gevent (работает на Python 3.12 и 3.13, в отличие от eventlet)
echo "    • Установка gevent..."
pip install --index-url https://pypi.org/simple/ --timeout=600 gevent gevent-websocket -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 gevent gevent-websocket
echo "      ✓ gevent установлен"

# Устанавливаем gunicorn
echo "    • Установка gunicorn..."
pip install --index-url https://pypi.org/simple/ --timeout=600 gunicorn -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 gunicorn
echo "      ✓ gunicorn установлен"

# Устанавливаем python-dotenv
echo "    • Установка python-dotenv..."
pip install --index-url https://pypi.org/simple/ --timeout=600 python-dotenv -q 2>/dev/null || \
    pip install --index-url https://pypi.org/simple/ --timeout=900 python-dotenv
echo "      ✓ python-dotenv установлен"

# Проверка установки
echo ""
echo "  • Проверка установленных пакетов:"
pip list 2>/dev/null | grep -E "Flask|flask-socketio|requests|schedule|gevent|gunicorn" | while read line; do
    echo "    ✓ $line"
done

# Деактивируем окружение
deactivate

echo ""
echo -e "${GREEN}✅ Python окружение готово${NC}"
echo ""

# ============================================
# ШАГ 4: СОЗДАНИЕ APP.PY
# ============================================
echo -e "${YELLOW}[4/7] Создание основного файла приложения (app.py)...${NC}"
echo ""

# Создаём app.py через heredoc
cat > $INSTALL_DIR/app/app.py << 'APPEOF'
#!/usr/bin/env python3
"""
TRASSIR Monitor v13.0 — Основной файл приложения
Полная версия с определением имён отключённых каналов

Функции:
- Мониторинг здоровья серверов TRASSIR через API /health
- Определение имён конкретных отключённых каналов через /objects/
- Алерты при проблемах (диски, камеры, CPU, архив)
- WebSocket для live-обновления дашборда
- Московское время (UTC+3)
- История и графики
"""

import os
import json
import sqlite3
import threading
import time
import re
import secrets
import hmac
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from flask import Flask, jsonify, render_template, request, session, redirect, url_for, make_response
from flask_cors import CORS
from flask_socketio import SocketIO
from werkzeug.security import generate_password_hash, check_password_hash
import requests
import schedule

# ============================================
# КОНФИГУРАЦИЯ ПРИЛОЖЕНИЯ
# ============================================
BASE_DIR = "/opt/trassir-monitor"
TEMPLATE_DIR = os.path.join(BASE_DIR, "templates")
DB_PATH = os.path.join(BASE_DIR, "data", "trassir.db")
LOG_DIR = os.path.join(BASE_DIR, "logs")
SECRET_KEY_PATH = os.path.join(BASE_DIR, "data", "secret_key.txt")
APP_VERSION = "v13.0"

# ============================================
# ИНИЦИАЛИЗАЦИЯ FLASK
# ============================================
app = Flask(__name__, template_folder=TEMPLATE_DIR)


def _read_installed_commit(module):
    """
    Читает короткий хеш коммита main, зафиксированный install-*.sh при
    последней успешной установке/обновлении ЭТОГО конкретного модуля
    (dashboard/telegram/mail — у каждого своя метка, потому что каждый
    может обновляться независимо от других). Файл лежит в data/,
    поэтому переживает обновление (см. "СВЕЖАЯ УСТАНОВКА ИЛИ
    ОБНОВЛЕНИЕ?" в install-trassir-monitor.sh) — это единственный
    реальный источник версии в этом проекте: $BASE_DIR НИКОГДА не
    git-чекаут ни для чего (все install-*.sh пишут файлы напрямую на
    диск через heredoc, см. CLAUDE.md "Editing means editing the
    heredoc directly"), так что метка, записанная установщиком через
    запрос к GitHub API в момент установки — единственный способ узнать
    это без постоянного живого git-чекаута только ради одной цифры.
    Отсутствие файла (модуль не установлен, установлен версией до этой
    правки, или установка проходила без доступа к GitHub) — просто "?",
    ожидаемый ответ, не ошибка.
    """
    path = os.path.join(BASE_DIR, "data", f".installed_commit_{module}")
    try:
        with open(path) as f:
            value = f.read().strip()
            return value if value else "?"
    except Exception:
        return "?"


def _get_build_info():
    """
    Информация о версии для футера дашборда/настроек — тот же принцип,
    что уже применён в launcher-trassir-monitor.sh: дата изменения
    САМОГО ФАЙЛА app.py на диске (когда код в последний раз
    сгенерировал установщик — меняется только при реальной установке
    или обновлении) плюс коммит, зафиксированный установщиком в
    data/.installed_commit_dashboard (см. _read_installed_commit).
    Считается ОДИН раз при старте процесса (модульная константа
    BUILD_INFO ниже), а не на каждый запрос — ни то, ни другое не
    меняется, пока сам процесс жив.
    """
    try:
        mtime = datetime.fromtimestamp(os.path.getmtime(__file__)).strftime("%Y-%m-%d %H:%M")
    except Exception:
        mtime = "?"

    return {"version": APP_VERSION, "mtime": mtime, "commit": _read_installed_commit("dashboard")}


BUILD_INFO = _get_build_info()


@app.context_processor
def inject_build_info():
    """
    Делает build_info доступным во ВСЕХ шаблонах автоматически, без
    ручной передачи в каждый render_template() по отдельности — иначе
    добавление этой информации в base.html потребовало бы находить и
    править каждый route, который вообще рендерит HTML.
    """
    return {"build_info": BUILD_INFO}


def _load_or_create_secret_key():
    """
    Секретный ключ для подписи сессий — должен переживать перезапуск
    сервиса (systemctl restart), иначе каждый рестарт разлогинивает
    всех пользователей и обесценивает "постоянную" сессию.
    Хранится отдельным файлом с правами 600 (не в БД, чтобы не
    зависеть от init_db()/схемы).
    """
    try:
        os.makedirs(os.path.dirname(SECRET_KEY_PATH), exist_ok=True)
        if os.path.exists(SECRET_KEY_PATH):
            with open(SECRET_KEY_PATH, "r") as f:
                key = f.read().strip()
            if key:
                return key
        key = secrets.token_hex(32)
        fd = os.open(SECRET_KEY_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(key)
        return key
    except Exception:
        # Не удалось сохранить/прочитать файл — работаем со случайным
        # ключом на этот процесс, чем падать при старте.
        return secrets.token_hex(32)


# Секретный ключ для сессий и безопасности
app.secret_key = _load_or_create_secret_key()

# Cookie сессии: HttpOnly (по умолчанию и так True, ставим явно, чтобы не
# зависеть от версии Flask) — JS не может прочитать cookie даже через XSS.
# SameSite=Lax — браузер не приложит cookie к межсайтовому запросу (кроме
# перехода по ссылке), то есть CSRF через чужую страницу, отправляющую
# fetch()/form на наш /api/..., не сработает без валидной сессии этого же
# сайта. Secure не включаем — README прямо поддерживает работу без SSL
# (локальная сеть без сертификата), а Secure-cookie браузер не отправит
# по обычному http.
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

# Включаем поддержку Cross-Origin Resource Sharing
CORS(app)

# Инициализация SocketIO для WebSocket (используем gevent — поддерживает Python 3.12+/3.13)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="gevent")

# Отключаем предупреждения SSL для самоподписанных сертификатов
requests.packages.urllib3.disable_warnings()

# ============================================
# АВТОРИЗАЦИЯ
# ============================================

from functools import wraps

def login_required(f):
    """Декоратор — только для авторизованных пользователей."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login_page"))
        return f(*args, **kwargs)
    return decorated

def is_logged_in():
    """Проверка авторизации для шаблонов."""
    return bool(session.get("logged_in"))


def verify_admin_password(password, stored):
    """
    Сравнивает введённый пароль с сохранённым значением.
    Поддерживает как новый формат (хеш werkzeug — pbkdf2:.../scrypt:...),
    так и старые записи в БД, сохранённые до этого изменения открытым
    текстом — иначе апгрейд кода на уже установленной системе мгновенно
    заблокировал бы вход существующим пользователям.
    """
    stored = stored or ""
    if stored.startswith(("pbkdf2:", "scrypt:")):
        try:
            return check_password_hash(stored, password)
        except Exception:
            return False
    # Старый формат — открытый текст, сравнение с постоянным временем
    return hmac.compare_digest(password.encode("utf-8", "ignore"), stored.encode("utf-8", "ignore"))


# ============================================
# ЗАЩИТА ОТ ПОДБОРА ПАРОЛЯ (login)
# ============================================
# Простой in-memory лимитер по IP — единственный воркер gunicorn
# (workers = 1, см. gunicorn_config.py), поэтому общий словарь в
# памяти процесса достаточен, без Redis/внешнего хранилища.
_login_attempts_lock = threading.Lock()
_login_attempts = {}  # ip -> {"count": int, "first_ts": float}
LOGIN_MAX_ATTEMPTS = 5
LOGIN_LOCKOUT_SECONDS = 300


def _login_is_locked_out(ip):
    with _login_attempts_lock:
        entry = _login_attempts.get(ip)
        if not entry:
            return False
        if time.time() - entry["first_ts"] > LOGIN_LOCKOUT_SECONDS:
            del _login_attempts[ip]
            return False
        return entry["count"] >= LOGIN_MAX_ATTEMPTS


def _login_register_failure(ip):
    with _login_attempts_lock:
        entry = _login_attempts.get(ip)
        now = time.time()
        if not entry or now - entry["first_ts"] > LOGIN_LOCKOUT_SECONDS:
            _login_attempts[ip] = {"count": 1, "first_ts": now}
        else:
            entry["count"] += 1


def _login_reset_attempts(ip):
    with _login_attempts_lock:
        _login_attempts.pop(ip, None)

# ============================================
# ГЛОБАЛЬНЫЙ КЭШ ДАННЫХ
# ============================================
# Хранит последние данные для быстрого доступа
servers_cache = []

# ============================================
# ФУНКЦИИ ДЛЯ РАБОТЫ С БАЗОЙ ДАННЫХ
# ============================================

def get_db():
    """
    Создаёт и возвращает подключение к базе данных SQLite.
    
    Настройки:
    - WAL режим для конкурентного доступа (чтение не блокирует запись)
    - busy_timeout для ожидания при блокировке
    - row_factory для доступа к полям по имени
    """
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """
    Инициализирует базу данных.
    Создаёт все необходимые таблицы, индексы и настройки по умолчанию.
    """
    conn = get_db()
    cursor = conn.cursor()
    
    # ============================================
    # Таблица servers — информация о серверах TRASSIR
    # ============================================
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS servers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            ip TEXT NOT NULL,
            port INTEGER DEFAULT 8080,
            sdk_password TEXT DEFAULT '',
            ssl BOOLEAN DEFAULT 1,
            enabled BOOLEAN DEFAULT 1,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # ============================================
    # Таблица health — история здоровья серверов
    # ============================================
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS health (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            ts DATETIME,
            cpu REAL,
            disks INT,
            ch_total INT,
            ch_online INT,
            arch REAL,
            uptime INT,
            rt INT,
            FOREIGN KEY (server_id) REFERENCES servers (id)
        )
    """)
    
    # ============================================
    # Таблица alerts — алерты о проблемах
    # ============================================
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            ts DATETIME,
            level TEXT,
            msg TEXT,
            ack BOOLEAN DEFAULT 0,
            FOREIGN KEY (server_id) REFERENCES servers (id)
        )
    """)

    # Миграция: колонка resolved_at (момент закрытия алерта — авто или
    # вручную). Без неё время простоя в уведомлениях о восстановлении
    # нечем считать (единственная альтернатива — время СОЗДАНИЯ алерта,
    # что и было ошибкой раньше). ALTER TABLE ADD COLUMN не поддерживает
    # IF NOT EXISTS в старых SQLite — проверяем через PRAGMA.
    existing_cols = {row["name"] for row in cursor.execute("PRAGMA table_info(alerts)").fetchall()}
    if "resolved_at" not in existing_cols:
        cursor.execute("ALTER TABLE alerts ADD COLUMN resolved_at DATETIME")

    # ============================================
    # Таблица settings — настройки системы
    # ============================================
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    
    # ============================================
    # Таблицы для Telegram нотифайера
    # ============================================
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS telegram_chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id TEXT UNIQUE NOT NULL,
            name TEXT DEFAULT '',
            enabled INTEGER DEFAULT 1,
            warning INTEGER DEFAULT 1,
            critical INTEGER DEFAULT 1,
            info INTEGER DEFAULT 0,
            added_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS telegram_settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS telegram_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts DATETIME,
            alert_key TEXT,
            chat_id TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tg_logs_key ON telegram_logs(alert_key, ts)")

    # ============================================
    # Таблицы для Mail нотифайера
    # ============================================
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS mail_recipients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            name TEXT DEFAULT '',
            enabled INTEGER DEFAULT 1,
            warning INTEGER DEFAULT 1,
            critical INTEGER DEFAULT 1,
            info INTEGER DEFAULT 0,
            added_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS mail_settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS mail_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts DATETIME,
            alert_key TEXT,
            recipient TEXT,
            subject TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_mail_logs_key ON mail_logs(alert_key, ts)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_health_srv_time ON health(server_id, ts)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_alerts_srv ON alerts(server_id, ack)")
    
    # ============================================
    # Настройки по умолчанию
    # ============================================
    default_settings = [
        ("poll_interval", "15"),
        ("retention_days", "30"),
        ("cpu_warning", "80"),
        ("cpu_critical", "95"),
        ("archive_warning_days", "14"),
        ("archive_critical_days", "7"),
        ("admin_password", generate_password_hash("admin")),
    ]
    
    for key, value in default_settings:
        cursor.execute(
            "INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)",
            (key, value)
        )
    
    conn.commit()
    conn.close()
    print("База данных инициализирована")


# ============================================
# КЛИЕНТ ДЛЯ РАБОТЫ С API TRASSIR
# ============================================

class TrassirClient:
    """
    Клиент для взаимодействия с API сервера TRASSIR.
    
    Поддерживает:
    - Авторизацию через SDK пароль
    - Получение здоровья сервера (/health)
    - Получение списка каналов и их состояний (/objects/)
    
    Параметры:
        ip: IP адрес сервера TRASSIR
        port: порт веб-сервера (по умолчанию 8080)
        ssl: использовать HTTPS (True/False)
        sdk_password: SDK пароль из настроек TRASSIR
    """
    
    def __init__(self, cfg):
        use_ssl = cfg.get("ssl", True)
        protocol = "https" if use_ssl else "http"
        self.url = f"{protocol}://{cfg['ip']}:{cfg.get('port', 8080)}"
        self.sdk = cfg.get("sdk_password", "")
        self.session = requests.Session()
        self.session.verify = False
    
    def get(self):
        """
        Получает данные о здоровье сервера через эндпоинт /health.
        
        Возвращает словарь:
            ok: 1 если успешно, 0 если ошибка
            cpu: загрузка процессора (%)
            disks: состояние дисков (1=OK, 0=проблема)
            ch_t: общее количество каналов
            ch_o: количество онлайн каналов
            uptime: время работы (сек)
            arch: глубина архива (дни)
            rt: время ответа (мс)
        """
        start_time = time.time()
        
        try:
            # Параметры запроса
            params = {"password": self.sdk} if self.sdk else {}
            
            # Выполняем GET запрос к /health
            response = self.session.get(
                f"{self.url}/health",
                params=params,
                timeout=10
            )
            
            # Вычисляем время ответа
            response_time = int((time.time() - start_time) * 1000)
            
            if response.status_code == 200:
                # Очищаем ответ от JavaScript-комментариев
                text = response.text
                text = re.sub(r'//.*?\n', '\n', text)
                text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
                
                # Извлекаем JSON из ответа
                match = re.search(r'\{.*\}', text, re.DOTALL)
                if match:
                    text = match.group(0)
                
                # Парсим JSON
                data = json.loads(text)
                
                return {
                    "ok": 1,
                    "cpu": float(data.get("cpu_load", 0)),
                    "disks": int(data.get("disks", 0)),
                    "ch_t": int(data.get("channels_total", 0)),
                    "ch_o": int(data.get("channels_online", 0)),
                    "uptime": int(data.get("uptime", 0)),
                    "arch": float(data.get("disks_stat_main_days", 0)),
                    "rt": response_time
                }
            
            return {
                "ok": 0,
                "err": f"HTTP {response.status_code}",
                "rt": response_time
            }
        
        except requests.exceptions.Timeout:
            return {
                "ok": 0,
                "err": "Таймаут соединения",
                "rt": int((time.time() - start_time) * 1000)
            }
        except requests.exceptions.ConnectionError:
            return {
                "ok": 0,
                "err": "Ошибка соединения",
                "rt": int((time.time() - start_time) * 1000)
            }
        except Exception as e:
            return {
                "ok": 0,
                "err": str(e),
                "rt": int((time.time() - start_time) * 1000)
            }
    
    def get_channels_info(self):
        """
        Получает список ВСЕХ каналов и проверяет состояние КАЖДОГО.
        
        Алгоритм:
        1. Запрашивает /objects/ — получает все объекты сервера
        2. Отфильтровывает только объекты класса "Channel"
        3. Для каждого канала запрашивает /objects/{GUID}
        4. Проверяет state_vector — если есть "Signal", канал онлайн
        
        Возвращает:
            ok: 1 если успешно
            channels: словарь {имя_канала: True/False}
                True = онлайн (есть Signal)
                False = офлайн
        """
        try:
            params = {"password": self.sdk} if self.sdk else {}
            
            # Шаг 1: получаем список всех объектов
            response = self.session.get(
                f"{self.url}/objects/",
                params=params,
                timeout=10
            )
            
            if response.status_code != 200:
                return {"ok": 0, "error": f"HTTP {response.status_code}"}
            
            all_objects = json.loads(response.text)
            
            # Шаг 2: отфильтровываем только каналы
            channels_list = []
            for obj in all_objects:
                if obj.get("class") == "Channel":
                    channels_list.append({
                        "guid": obj.get("guid", ""),
                        "name": obj.get("name", "Unknown")
                    })
            
            print(f"  Найдено каналов: {len(channels_list)}")
            
            # Шаг 3: для каждого канала запрашиваем его состояние
            #
            # channels_status — словарь {имя_канала: bool}, а alerts.msg
            # хранит именно ИМЯ, не guid, так что если в TRASSIR у двух
            # разных каналов совпадает имя (это ничем не запрещено на
            # уровне SDK), их статусы здесь схлопываются в один ключ.
            # Живая жалоба "камера восстановилась, а алерт не закрывается"
            # с высокой вероятностью — ровно этот случай: например, канал
            # с именем "Двор" удалили и создали заново под тем же именем,
            # или две камеры изначально называются одинаково. Без явной
            # обработки последний обработанный канал в JSON-ответе молча
            # перезаписывал бы статус предыдущего одноимённого — то есть
            # "онлайн" одного мог случайно скрыть "офлайн" другого (и
            # алерт закрылся бы неправильно, когда камера, о которой он
            # реально был, всё ещё не работает) — либо наоборот, "офлайн"
            # мог держать алерт открытым даже когда РЕАЛЬНАЯ камера,
            # создавшая алерт, уже восстановилась. Схлопываем консервативно
            # через AND — "онлайн" только если ВСЕ одноимённые каналы
            # онлайн — так алерт никогда не закроется по ошибке, только,
            # в худшем случае, откроется чуть дольше, чем нужно.
            channels_status = {}
            duplicate_names_warned = set()
            for i, ch in enumerate(channels_list):
                try:
                    ch_response = self.session.get(
                        f"{self.url}/objects/{ch['guid']}",
                        params=params,
                        timeout=5
                    )

                    if ch_response.status_code == 200:
                        ch_data = json.loads(ch_response.text)
                        state_vector = ch_data.get("state_vector", [])
                        is_online = "Signal" in state_vector
                    else:
                        is_online = False
                except Exception as e:
                    is_online = False
                    print(f"  ⚠ Ошибка для канала {ch['name']}: {e}")

                name = ch["name"]
                if name in channels_status:
                    if name not in duplicate_names_warned:
                        duplicate_names_warned.add(name)
                        print(f"  ⚠ Несколько каналов с именем '{name}' в TRASSIR — "
                              f"алерты по камерам сопоставляются по ИМЕНИ, поэтому статус "
                              f"объединён как 'онлайн, только если все одноимённые каналы онлайн'")
                    channels_status[name] = channels_status[name] and is_online
                else:
                    channels_status[name] = is_online

                # Выводим прогресс для большого количества каналов
                if (i + 1) % 10 == 0:
                    print(f"  Проверено {i + 1}/{len(channels_list)} каналов...")

            return {"ok": 1, "channels": channels_status}
        
        except Exception as e:
            return {"ok": 0, "error": str(e)}


# ============================================
# СБОР ДАННЫХ СО ВСЕХ СЕРВЕРОВ
# ============================================

def _fetch_server_data(server, servers_with_open_cam_alerts):
    """
    Сетевой опрос ОДНОГО сервера — HTTP к самому TRASSIR, без единого
    обращения к БД. Специально вынесено в отдельную функцию, чтобы её
    можно было безопасно запускать параллельно в пуле потоков (см.
    collect()) — sqlite-соединение при этом остаётся одно и живёт
    только в основном потоке, здесь мы его не трогаем вообще.

    Раньше collect() опрашивал серверы последовательно, с таймаутом
    10 сек на каждый (TrassirClient.get()) — при N серверах и хотя бы
    парах недоступных одновременно (ровно сценарий из нагрузочного
    теста: несколько регистраторов падают разом) один цикл опроса мог
    растянуться на N×10 сек, легко перекрыв сам poll_interval
    (по умолчанию 15 сек) и провоцируя наложение циклов друг на друга.
    Теперь все N серверов опрашиваются одновременно — весь цикл
    ограничен ХУДШИМ из таймаутов, а не их суммой.
    """
    server_id = server["id"]
    client = TrassirClient({
        "ip": server["ip"],
        "port": server["port"],
        "ssl": bool(server["ssl"]),
        "sdk_password": server["sdk_password"]
    })

    health = client.get()
    channels_info = None

    if health["ok"] and (health["ch_t"] > health["ch_o"] or server_id in servers_with_open_cam_alerts):
        try:
            channels_info = client.get_channels_info()
        except Exception as e:
            print(f"  {server['name']}: ошибка получения каналов: {e}")

    return server_id, health, channels_info


def collect():
    """
    Основная функция сбора данных.
    
    Для каждого активного сервера:
    1. Запрашивает /health
    2. Если есть отвал камер — запрашивает имена каналов
    3. Генерирует алерты при проблемах
    4. Сохраняет всё в БД
    5. Отправляет обновления через WebSocket
    """
    global servers_cache
    
    try:
        # Подключаемся к БД
        conn = get_db()
        
        # Получаем список всех активных серверов
        servers = conn.execute(
            "SELECT * FROM servers WHERE enabled = 1"
        ).fetchall()
        
        # Загружаем настройки
        settings = dict(conn.execute(
            "SELECT key, value FROM settings"
        ).fetchall())
        
        updates = []

        # Какие серверы уже имеют активный алерт "камера офлайн" — считаем
        # ОДНИМ запросом заранее (а не по одному внутри цикла на сервер,
        # как было раньше), чтобы решение "нужен ли get_channels_info()"
        # для параллельного опроса не требовало доступа к БД из потоков.
        servers_with_open_cam_alerts = {
            row["server_id"] for row in conn.execute(
                "SELECT DISTINCT server_id FROM alerts WHERE msg LIKE 'Камера офлайн:%' AND ack = 0"
            ).fetchall()
        }

        # Опрашиваем все серверы ОДНОВРЕМЕННО (см. _fetch_server_data) —
        # весь цикл ограничен худшим таймаутом, а не суммой N таймаутов.
        fetched = {}
        if servers:
            with ThreadPoolExecutor(max_workers=min(len(servers), 20)) as executor:
                futures = [
                    executor.submit(_fetch_server_data, server, servers_with_open_cam_alerts)
                    for server in servers
                ]
                for future in as_completed(futures):
                    fetched_server_id, fetched_health, fetched_channels_info = future.result()
                    fetched[fetched_server_id] = (fetched_health, fetched_channels_info)

        # Дальше — обычная последовательная обработка результатов и запись
        # в БД одним соединением (sqlite3-соединения не потокобезопасны
        # между собой, поэтому все INSERT/UPDATE остаются в основном потоке,
        # распараллелен только медленный сетевой опрос выше).
        for server in servers:
            server_id = server["id"]
            server_name = server["name"]

            health, channels_info = fetched[server_id]

            if health["ok"]:
                # ============================================
                # Сохраняем в историю
                # ============================================
                conn.execute("""
                    INSERT INTO health (
                        server_id, ts, cpu, disks,
                        ch_total, ch_online, arch, uptime, rt
                    ) VALUES (
                        ?, datetime('now', '+3 hours'), ?, ?,
                        ?, ?, ?, ?, ?
                    )
                """, (
                    server_id,
                    health["cpu"],
                    health["disks"],
                    health["ch_t"],
                    health["ch_o"],
                    health["arch"],
                    health["uptime"],
                    health["rt"]
                ))
                conn.commit()  # ← ВАЖНО! Сохраняем health сразу

                # ============================================
                # ВОССТАНОВЛЕНИЕ СЕРВЕРА (был недоступен — теперь ответил)
                # ============================================
                conn.execute("""
                    UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours')
                    WHERE server_id = ? AND msg LIKE 'Сервер недоступен:%' AND ack = 0
                """, (server_id,))
                conn.commit()

                # channels_info уже получен параллельно в _fetch_server_data()
                # (см. начало collect()) — здесь только раскладываем его на
                # offline_names, сетевой запрос сюда не переносим.
                offline_names = []
                if channels_info and channels_info.get("ok"):
                    for ch_name, is_online in channels_info["channels"].items():
                        if not is_online:
                            offline_names.append(ch_name)
                    print(f"  {server_name}: офлайн каналов: {len(offline_names)}")

                # ============================================
                # ВОССТАНОВЛЕНИЕ — ЗАКРЫВАЕМ АЛЕРТЫ ПО КАМЕРАМ
                # ============================================
                if channels_info and channels_info.get("ok"):
                    all_channels = channels_info["channels"]
                    active_cam_alerts = conn.execute(
                        "SELECT id, msg FROM alerts WHERE server_id = ? AND msg LIKE 'Камера офлайн:%' AND ack = 0",
                        (server_id,)
                    ).fetchall()
                    for alert in active_cam_alerts:
                        # Извлекаем имя камеры из сообщения "Камера офлайн: CamName"
                        cam_name = alert["msg"].replace("Камера офлайн: ", "").strip()
                        # Сопоставление идёт по ИМЕНИ канала (в alerts.msg не
                        # хранится guid) — если канал переименован/удалён в
                        # TRASSIR, автоматика не может отличить "уже
                        # восстановился" от "больше не существует под этим
                        # именем" и намеренно НЕ закрывает алерт сама (тихое
                        # автозакрытие в этом случае рискованнее, чем алерт,
                        # который придётся закрыть вручную через "Сбросить" —
                        # см. новую кнопку у каждого алерта в server.html).
                        # Печатаем явно, чтобы при живой жалобе "камера
                        # восстановилась, а алерт висит" сразу было видно,
                        # какая именно из двух причин это в конкретном случае.
                        if cam_name not in all_channels:
                            print(f"  ⚠ {server_name}: алерт «Камера офлайн: {cam_name}» не закрыт — "
                                  f"канала с таким именем сейчас нет в списке TRASSIR "
                                  f"(переименован или удалён?), сбросить вручную кнопкой у алерта")
                        elif all_channels.get(cam_name, False):
                            conn.execute(
                                "UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours') WHERE id = ?",
                                (alert["id"],)
                            )
                            conn.commit()
                            print(f"  ✅ {server_name}: камера восстановлена: {cam_name}")
                elif health["ch_o"] == health["ch_t"]:
                    # Все камеры онлайн по health — закрываем все камерные алерты
                    conn.execute("""
                        UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours')
                        WHERE server_id = ? AND msg LIKE 'Камера офлайн:%' AND ack = 0
                    """, (server_id,))
                    conn.commit()
                elif server_id in servers_with_open_cam_alerts:
                    # channels_info не удалось получить в этом опросе (ошибка
                    # /objects/, таймаут — см. get_channels_info()), а health
                    # говорит, что онлайн ещё не ВСЕ камеры — значит, если
                    # восстановилась ЧАСТЬ (не все) камер этого сервера, узнать
                    # КАКАЯ именно без списка каналов невозможно, и ни один
                    # алерт в этом цикле опроса намеренно не трогаем (закрыть
                    # не ту камеру было бы хуже, чем оставить всё как есть на
                    # один цикл). Раньше это было полностью тихо — при живой
                    # жалобе "восстановилась одна из нескольких камер, но
                    # алерты не закрылись" это выглядело как зависший баг,
                    # хотя на деле обычно самовосстанавливается на следующем
                    # опросе, как только /objects/ снова ответит нормально.
                    print(f"  ⚠ {server_name}: не удалось получить список каналов в этом опросе "
                          f"({channels_info.get('error') if channels_info else 'нет ответа'}) — "
                          f"открытые алерты по камерам проверятся заново на следующем опросе")

                # ============================================
                # ГЕНЕРАЦИЯ АЛЕРТОВ ПО КАМЕРАМ — ОДИН НА КАМЕРУ
                # ============================================
                for cam_name in offline_names:
                    message = f"Камера офлайн: {cam_name}"
                    existing = conn.execute(
                        "SELECT id FROM alerts WHERE server_id = ? AND msg = ? AND ack = 0",
                        (server_id, message)
                    ).fetchone()
                    if not existing:
                        conn.execute(
                            "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), 'warning', ?)",
                            (server_id, message)
                        )
                        print(f"  ⚠ {server_name}: новый алерт — {message}")
                conn.commit()

                # ============================================
                # ГЕНЕРАЦИЯ АЛЕРТОВ — CPU, ДИСКИ, АРХИВ
                # ============================================
                alerts_list = []

                if health["disks"] == 0:
                    alerts_list.append(("critical", "Ошибка дисков"))

                # CPU и архив — сначала критический порог (он строже),
                # иначе критическая нагрузка никогда не будет замечена
                # отдельно от обычного предупреждения.
                cpu_warning = float(settings.get("cpu_warning", 80))
                cpu_critical = float(settings.get("cpu_critical", 95))
                if health["cpu"] >= cpu_critical:
                    alerts_list.append(("critical", f"CPU: {health['cpu']:.1f}%"))
                elif health["cpu"] >= cpu_warning:
                    alerts_list.append(("warning", f"CPU: {health['cpu']:.1f}%"))

                # Архив измеряется в днях ДО конца, поэтому "критично" —
                # это МЕНЬШЕЕ число дней, чем "предупреждение".
                arch_warning = float(settings.get("archive_warning_days", 14))
                arch_critical = float(settings.get("archive_critical_days", 7))
                if health["arch"] <= arch_critical:
                    alerts_list.append(("critical", f"Архив: {health['arch']:.1f} дн"))
                elif health["arch"] <= arch_warning:
                    alerts_list.append(("warning", f"Архив: {health['arch']:.1f} дн"))

                # ============================================
                # АВТОЗАКРЫТИЕ CPU, АРХИВА, ДИСКОВ
                # ============================================
                active_types = {msg.split(":")[0].split("(")[0].strip() for _, msg in alerts_list}

                if "CPU" not in active_types:
                    conn.execute("UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours') WHERE server_id = ? AND msg LIKE 'CPU:%' AND ack = 0", (server_id,))
                if "Ошибка дисков" not in active_types:
                    conn.execute("UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours') WHERE server_id = ? AND msg = 'Ошибка дисков' AND ack = 0", (server_id,))
                if "Архив" not in active_types:
                    conn.execute("UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours') WHERE server_id = ? AND msg LIKE 'Архив:%' AND ack = 0", (server_id,))
                conn.commit()
                
                for level, message in alerts_list:
                    if message.startswith("CPU:"):
                        existing = conn.execute(
                            "SELECT id, msg, level FROM alerts WHERE server_id = ? AND msg LIKE 'CPU:%' AND ack = 0",
                            (server_id,)
                        ).fetchone()
                        if existing:
                            # Обновляем и текст, и уровень — иначе переход
                            # warning -> critical (или обратно) остаётся
                            # незамеченным до следующего ack.
                            if existing["msg"] != message or existing["level"] != level:
                                conn.execute(
                                    "UPDATE alerts SET msg = ?, level = ? WHERE id = ?",
                                    (message, level, existing["id"])
                                )
                                conn.commit()
                        else:
                            conn.execute(
                                "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), ?, ?)",
                                (server_id, level, message)
                            )
                            conn.commit()
                    elif message.startswith("Архив:"):
                        existing = conn.execute(
                            "SELECT id, msg, level FROM alerts WHERE server_id = ? AND msg LIKE 'Архив:%' AND ack = 0",
                            (server_id,)
                        ).fetchone()
                        if existing:
                            if existing["msg"] != message or existing["level"] != level:
                                conn.execute(
                                    "UPDATE alerts SET msg = ?, level = ? WHERE id = ?",
                                    (message, level, existing["id"])
                                )
                                conn.commit()
                        else:
                            conn.execute(
                                "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), ?, ?)",
                                (server_id, level, message)
                            )
                            conn.commit()
                    else:
                        # Диски — точное совпадение
                        existing = conn.execute(
                            "SELECT id FROM alerts WHERE server_id = ? AND msg = ? AND ack = 0",
                            (server_id, message)
                        ).fetchone()
                        if not existing:
                            conn.execute(
                                "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), ?, ?)",
                                (server_id, level, message)
                            )
                            conn.commit()
                                            
                # ============================================
                # ДАННЫЕ ДЛЯ WEBSOCKET
                # ============================================
                updates.append({
                    "id": server_id,
                    "name": server_name,
                    "ip": server["ip"],
                    "ok": 1,
                    "cpu": health["cpu"],
                    "ch_t": health["ch_t"],
                    "ch_o": health["ch_o"],
                    "arch": health["arch"],
                    "uptime_d": round(health["uptime"] / 86400, 1),
                    "uptime_s": health["uptime"],
                    "disks": health["disks"],
                    "rt": health["rt"],
                    "alerts": conn.execute(
                        "SELECT COUNT(*) as cnt FROM alerts WHERE server_id = ? AND ack = 0",
                        (server_id,)
                    ).fetchone()["cnt"]
                })
            else:
                # ============================================
                # СЕРВЕР НЕДОСТУПЕН — один алерт на инцидент, без спама
                # ============================================
                err_text = health.get("err", "нет ответа")
                message = f"Сервер недоступен: {err_text}"
                existing = conn.execute(
                    "SELECT id FROM alerts WHERE server_id = ? AND msg LIKE 'Сервер недоступен:%' AND ack = 0",
                    (server_id,)
                ).fetchone()
                if not existing:
                    conn.execute(
                        "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), 'critical', ?)",
                        (server_id, message)
                    )
                    print(f"  🔴 {server_name}: {message}")
                conn.commit()

                updates.append({
                    "id": server_id,
                    "name": server_name,
                    "ip": server["ip"],
                    "ok": 0,
                    "alerts": conn.execute(
                        "SELECT COUNT(*) as cnt FROM alerts WHERE server_id = ? AND ack = 0",
                        (server_id,)
                    ).fetchone()["cnt"]
                })

        # Сохраняем в кэш
        servers_cache = updates
        
        # Отправляем обновления через WebSocket
        if updates:
            socketio.emit('update', {'servers': updates})
        
        conn.commit()  # ← Финальный commit
        conn.close()
        
    except Exception as e:
        print(f"Ошибка при сборе данных: {e}")


def cleanup_old_data():
    """
    Удаляет данные старше retention_days (настройка "Хранение данных").
    Без этой функции таблица health растёт неограниченно — при
    poll_interval=15с это ~5760 строк/сервер/сутки.

    - health: удаляется вся история старше порога (нужна только для
      графиков за последние 6ч/24ч/7д).
    - alerts: удаляются только уже ЗАКРЫТЫЕ (ack=1) алерты — активные
      проблемы никогда не трогаем, независимо от возраста.
    - telegram_logs/mail_logs: строка "получателю X отправлен алерт N"
      растёт с числом получателей × числом алертов, а не только со
      временем — при 5+ серверах и нескольких получателях это реальный
      объём. Раньше каждый бот сам чистил свой лог по ФИКСИРОВАННОМУ
      7-дневному таймеру, независимо от retention_days и, что хуже,
      независимо от того, закрыт ли сам алерт: если проблема оставалась
      открытой дольше 7 дней (например, стабильно низкий архив), запись
      об уже отправленном уведомлении удалялась раньше, чем сам алерт —
      и на следующем опросе бот считал этот алерт "новым" и слал его
      повторно, хотя ничего не изменилось. Теперь лог чистится в этой
      же функции и по тому же принципу, что alerts: строка об отправке
      удаляется ТОЛЬКО когда сам алерт уже удалён выше (значит закрыт и
      старше retention_days) — то есть не раньше и не позже жизни
      самого алерта, отдельного таймера больше нет.
    """
    try:
        conn = get_db()
        settings = dict(conn.execute("SELECT key, value FROM settings").fetchall())
        days = int(float(settings.get("retention_days", 30) or 30))
        if days > 0:
            cutoff = f"-{days} days"
            conn.execute("DELETE FROM health WHERE ts < datetime('now', '+3 hours', ?)", (cutoff,))
            conn.execute("DELETE FROM alerts WHERE ack = 1 AND ts < datetime('now', '+3 hours', ?)", (cutoff,))
            # alert_key — это либо "N", либо "recovery_N", где N = alerts.id.
            # Строка лога осиротела (её алерта больше нет в таблице выше) —
            # значит её самой можно больше не хранить.
            conn.execute("""
                DELETE FROM telegram_logs
                WHERE CAST(REPLACE(alert_key, 'recovery_', '') AS INTEGER) NOT IN (SELECT id FROM alerts)
            """)
            conn.execute("""
                DELETE FROM mail_logs
                WHERE CAST(REPLACE(alert_key, 'recovery_', '') AS INTEGER) NOT IN (SELECT id FROM alerts)
            """)
            conn.commit()
            print(f"Очистка старых данных: удалены записи старше {days} дн.")
        conn.close()
    except Exception as e:
        print(f"Ошибка очистки старых данных: {e}")

# ============================================
# ПЛАНИРОВЩИК
# ============================================

def scheduler():
    """
    Запускает периодический сбор данных.
    Интервал настраивается в settings (по умолчанию 15 секунд).
    Запускается в отдельном потоке при старте приложения.
    """
    conn = get_db()
    settings = dict(conn.execute("SELECT key, value FROM settings").fetchall())
    conn.close()

    interval = int(settings.get("poll_interval", 15))
    print(f"Планировщик запущен, интервал: {interval} секунд")

    # Настраиваем периодический запуск
    schedule.every(interval).seconds.do(collect)
    schedule.every(1).hours.do(cleanup_old_data)

    # Первый сбор через 5 секунд после старта
    time.sleep(5)
    collect()
    cleanup_old_data()

    # Бесконечный цикл
    while True:
        schedule.run_pending()
        time.sleep(1)


# ============================================
# WEBSOCKET СОБЫТИЯ
# ============================================

@socketio.on("connect")
def handle_connect():
    """Клиент подключился к WebSocket"""
    pass


@socketio.on("disconnect")
def handle_disconnect():
    """Клиент отключился от WebSocket"""
    pass


# ============================================
# МАРШРУТЫ (ROUTES)
# ============================================

@app.route("/login", methods=["GET", "POST"])
def login_page():
    error = None
    if request.method == "POST":
        client_ip = request.remote_addr or "unknown"
        if _login_is_locked_out(client_ip):
            error = "Слишком много неудачных попыток. Попробуйте позже."
            return render_template("login.html", error=error)

        conn = get_db()
        settings = dict(conn.execute("SELECT key, value FROM settings").fetchall())
        conn.close()
        password = request.form.get("password", "")
        stored_password = settings.get("admin_password", "")
        if verify_admin_password(password, stored_password):
            _login_reset_attempts(client_ip)
            session["logged_in"] = True
            session.permanent = True
            return redirect(url_for("index"))
        else:
            _login_register_failure(client_ip)
            error = "Неверный пароль"
    return render_template("login.html", error=error)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


@app.route("/")
def index():
    """
    Главная страница — дашборд со списком всех серверов.
    Показывает:
    - Статистику по всем серверам
    - Список серверов с их метриками
    - Кнопки управления (добавить, редактировать, удалить)
    """
    conn = get_db()
    
    # Получаем все активные серверы
    servers = conn.execute(
        "SELECT * FROM servers WHERE enabled = 1 ORDER BY name"
    ).fetchall()
    
    # Инициализируем статистику
    stats = {
        "total_servers": len(servers),
        "total_cameras": 0,
        "online_cameras": 0,
        "total_alerts": 0
    }
    
    servers_data = []
    
    # Обрабатываем каждый сервер
    for server in servers:
        # Пробуем найти данные в кэше (самые свежие)
        cached = None
        for item in servers_cache:
            if item.get("id") == server["id"]:
                cached = item
                break
        
        if cached and cached.get("ok"):
            # Используем свежие данные из кэша
            health_data = {
                "ch_total": cached.get("ch_t", 0),
                "ch_online": cached.get("ch_o", 0),
                "cpu": cached.get("cpu", 0),
                "disks": cached.get("disks", 0),
                "arch": cached.get("arch", 0),
                "uptime": cached.get("uptime_s", 0),
                "rt": cached.get("rt", 0)
            }
        else:
            # Берём последнюю запись из БД
            health_row = conn.execute(
                "SELECT * FROM health WHERE server_id = ? ORDER BY ts DESC LIMIT 1",
                (server["id"],)
            ).fetchone()
            
            if health_row:
                health_data = {
                    "ch_total": health_row["ch_total"],
                    "ch_online": health_row["ch_online"],
                    "cpu": health_row["cpu"],
                    "disks": health_row["disks"],
                    "arch": health_row["arch"],
                    "uptime": health_row["uptime"],
                    "rt": health_row["rt"]
                }
            else:
                health_data = None
        
        # Обновляем статистику
        if health_data:
            stats["total_cameras"] += health_data["ch_total"]
            stats["online_cameras"] += health_data["ch_online"]
        
        # Количество активных алертов
        alerts_count = conn.execute(
            "SELECT COUNT(*) as cnt FROM alerts WHERE server_id = ? AND ack = 0",
            (server["id"],)
        ).fetchone()["cnt"]
        
        stats["total_alerts"] += alerts_count

        server_public = dict(server)
        server_public.pop("sdk_password", None)
        servers_data.append({
            "s": server_public,
            "h": health_data,
            "a": alerts_count
        })
    
    conn.close()
    
    return render_template(
        "dashboard.html",
        servers=servers_data,
        stats=stats,
        logged_in=is_logged_in()
    )


@app.route("/server/<int:server_id>")
def server_detail(server_id):
    """
    Детальная страница конкретного сервера.
    Показывает:
    - Текущие метрики (CPU, камеры, диски, архив, uptime, отклик)
    - График за 24 часа (CPU, камеры, архив)
    - Список алертов с возможностью сброса
    """
    conn = get_db()
    
    # Информация о сервере
    server = conn.execute(
        "SELECT * FROM servers WHERE id = ?",
        (server_id,)
    ).fetchone()
    
    if not server:
        conn.close()
        return "Сервер не найден", 404
    
    # История за последние 24 часа
    history = conn.execute("""
        SELECT * FROM health 
        WHERE server_id = ? 
        AND ts > datetime('now', '+3 hours', '-24 hours') 
        ORDER BY ts
    """, (server_id,)).fetchall()
    
    # Активные алерты (не закрытые)
    alerts_active = conn.execute("""
        SELECT * FROM alerts 
        WHERE server_id = ? AND ack = 0
        ORDER BY ts DESC
    """, (server_id,)).fetchall()
    
    # История закрытых алертов (последние 20)
    alerts_history = conn.execute("""
        SELECT * FROM alerts 
        WHERE server_id = ? AND ack = 1
        ORDER BY ts DESC
        LIMIT 20
    """, (server_id,)).fetchall()
    
    # Текущее состояние (последняя запись)
    current = conn.execute("""
        SELECT * FROM health 
        WHERE server_id = ? 
        ORDER BY ts DESC 
        LIMIT 1
    """, (server_id,)).fetchone()
    
    conn.close()

    server_public = dict(server)
    server_public.pop("sdk_password", None)

    return render_template(
        "server.html",
        server=server_public,
        history=[dict(h) for h in history],
        cur=dict(current) if current else None,
        alerts_active=[dict(a) for a in alerts_active],
        alerts_history=[dict(a) for a in alerts_history],
        logged_in=is_logged_in()
    )


@app.route("/settings")
def settings_page():
    conn = get_db()

    servers = conn.execute("SELECT * FROM servers ORDER BY name").fetchall()
    settings_dict = dict(conn.execute("SELECT key, value FROM settings").fetchall())

    # Определяем какие службы установлены
    has_telegram = os.path.exists(os.path.join(BASE_DIR, "app", "tg_bot.py")) or \
                   os.path.exists(os.path.join(BASE_DIR, "app", "tg_proxy_bot.py"))
    has_mail     = os.path.exists(os.path.join(BASE_DIR, "app", "mail_bot.py"))

    # Данные telegram (только если авторизован и служба есть)
    tg_chats    = []
    tg_settings = {}
    if has_telegram and is_logged_in():
        try:
            tg_chats = [dict(r) for r in conn.execute("SELECT * FROM telegram_chats ORDER BY id").fetchall()]
            tg_settings = dict(conn.execute("SELECT key, value FROM telegram_settings").fetchall())
        except Exception:
            pass

    # Данные mail (только если авторизован и служба есть)
    mail_recipients = []
    mail_settings   = {}
    if has_mail and is_logged_in():
        try:
            mail_recipients = [dict(r) for r in conn.execute("SELECT * FROM mail_recipients ORDER BY id").fetchall()]
            mail_settings   = dict(conn.execute("SELECT key, value FROM mail_settings").fetchall())
        except Exception:
            pass

    conn.close()

    servers_public = []
    for s in servers:
        s_dict = dict(s)
        s_dict.pop("sdk_password", None)
        servers_public.append(s_dict)

    return render_template(
        "settings.html",
        servers=servers_public,
        settings=settings_dict,
        logged_in=is_logged_in(),
        has_telegram=has_telegram,
        has_mail=has_mail,
        tg_chats=tg_chats,
        tg_settings=tg_settings,
        mail_recipients=mail_recipients,
        mail_settings=mail_settings
    )

# ============================================
# API ENDPOINTS
# ============================================

@app.route("/api/health/<int:server_id>")
def api_health(server_id):
    """
    API: получить текущее здоровье сервера напрямую из TRASSIR.
    Используется для автообновления метрик на детальной странице.
    """
    conn = get_db()
    server = conn.execute(
        "SELECT * FROM servers WHERE id = ?",
        (server_id,)
    ).fetchone()
    conn.close()
    
    if not server:
        return jsonify({"ok": 0, "err": "Сервер не найден"}), 404
    
    client = TrassirClient({
        "ip": server["ip"],
        "port": server["port"],
        "ssl": bool(server["ssl"]),
        "sdk_password": server["sdk_password"]
    })
    
    result = client.get()
    return jsonify(result)


HIST_MAX_POINTS = 60


def _aggregate_history(rows):
    """
    Схлопывает историю до HIST_MAX_POINTS точек усреднением по чанкам —
    ровно тот же алгоритм, что раньше выполнялся в браузере
    (loadHistory() в server.html: шаг = ceil(N/60), метка времени —
    середина чанка, cpu/arch — среднее, ch_online/ch_total — среднее
    округлённое). Перенесено на сервер, чтобы не гонять по сети сырые
    ~40000 строк (7 дней при опросе раз в 15 сек, ~6МБ JSON) ради
    графика, который всё равно показывает не больше 60 точек — сама
    картинка не меняется, только объём трафика на её построение.
    """
    if len(rows) <= HIST_MAX_POINTS:
        return rows
    step = -(-len(rows) // HIST_MAX_POINTS)  # ceil без импорта math
    aggregated = []
    for i in range(0, len(rows), step):
        chunk = rows[i:i + step]
        mid = chunk[len(chunk) // 2]
        n = len(chunk)
        aggregated.append({
            "ts": mid["ts"],
            "cpu": sum(r["cpu"] or 0 for r in chunk) / n,
            "ch_online": round(sum(r["ch_online"] or 0 for r in chunk) / n),
            "ch_total": round(sum(r["ch_total"] or 0 for r in chunk) / n),
            "arch": sum(r["arch"] or 0 for r in chunk) / n,
        })
    return aggregated


@app.route("/api/hist/<int:server_id>")
def api_history(server_id):
    """
    API: получить историю здоровья сервера для графика.

    Параметры:
        h (опционально): количество часов (по умолчанию 0.5)

    Если сырых точек в выбранном диапазоне больше HIST_MAX_POINTS,
    возвращается уже агрегированный (усреднённый по чанкам) ряд — см.
    _aggregate_history(). Иначе — сырые строки как есть, без изменений
    по сравнению с прежним поведением.
    """
    hours = request.args.get("h", 0.5, type=float)

    conn = get_db()
    history = conn.execute("""
        SELECT * FROM health
        WHERE server_id = ?
        AND ts > datetime('now', '+3 hours', ?)
        ORDER BY ts
    """, (server_id, f'-{hours} hours')).fetchall()
    conn.close()

    rows = [dict(h) for h in history]
    return jsonify(_aggregate_history(rows))


@app.route("/api/servers", methods=["GET", "POST", "PUT", "DELETE"])
def api_servers():
    conn = get_db()
    
    if request.method == "GET":
        servers = conn.execute("SELECT * FROM servers ORDER BY name").fetchall()
        conn.close()
        # SDK-пароль никогда не отдаётся через API — ни авторизованным,
        # ни анонимным клиентам (форма редактирования и так не нуждается
        # в реальном значении: пустое поле = "оставить как есть").
        result = []
        for s in servers:
            s_dict = dict(s)
            s_dict["has_password"] = bool(s_dict.pop("sdk_password", ""))
            result.append(s_dict)
        return jsonify(result)

    # Все изменения только для авторизованных
    if not session.get("logged_in"):
        conn.close()
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403
    
    elif request.method == "POST":
        # Добавление нового сервера
        data = request.json
        
        conn.execute("""
            INSERT INTO servers (name, ip, port, sdk_password, ssl)
            VALUES (?, ?, ?, ?, ?)
        """, (
            data.get("name"),
            data.get("ip"),
            data.get("port", 8080),
            data.get("sdk_password", ""),
            data.get("ssl", True)
        ))
        conn.commit()
        conn.close()
        
        # Запускаем немедленный сбор данных в фоне
        threading.Thread(target=collect).start()
        
        return jsonify({"ok": 1, "message": "Сервер добавлен"})
    
    elif request.method == "PUT":
        # Изменение существующего сервера
        data = request.json
        server_id = data.get("id")
        sdk_password = data.get("sdk_password", "")
        
        if sdk_password:
            # Обновляем с новым паролем
            conn.execute("""
                UPDATE servers 
                SET name = ?, ip = ?, port = ?, sdk_password = ?, ssl = ?
                WHERE id = ?
            """, (
                data.get("name"),
                data.get("ip"),
                data.get("port", 8080),
                sdk_password,
                data.get("ssl", True),
                server_id
            ))
        else:
            # Обновляем без изменения пароля
            conn.execute("""
                UPDATE servers 
                SET name = ?, ip = ?, port = ?, ssl = ?
                WHERE id = ?
            """, (
                data.get("name"),
                data.get("ip"),
                data.get("port", 8080),
                data.get("ssl", True),
                server_id
            ))
        
        conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Сервер обновлён"})
    
    elif request.method == "DELETE":
        # Удаление сервера
        server_id = request.args.get("id")
        
        if server_id:
            # Удаляем связанные данные
            conn.execute("DELETE FROM health WHERE server_id = ?", (server_id,))
            conn.execute("DELETE FROM alerts WHERE server_id = ?", (server_id,))
            conn.execute("DELETE FROM servers WHERE id = ?", (server_id,))
            conn.commit()
        
        conn.close()
        return jsonify({"ok": 1, "message": "Сервер удалён"})


@app.route("/api/servers/export")
def export_servers():
    """
    Экспорт списка серверов ВМЕСТЕ с SDK-паролями — для резервной копии
    или переноса на другую установку. Обычный GET /api/servers никогда
    не отдаёт реальный пароль (только has_password: true/false) — здесь
    пароль отдаётся намеренно, иначе импорт на другой установке был бы
    бесполезен (пароли пришлось бы вбивать заново вручную для каждого
    сервера). Именно поэтому этот READ-эндпоинт, в отличие от обычного
    чтения списка серверов, всё равно требует авторизации — как любое
    действие, раскрывающее секреты.
    """
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403

    conn = get_db()
    servers = conn.execute(
        "SELECT name, ip, port, sdk_password, ssl, enabled FROM servers ORDER BY name"
    ).fetchall()
    conn.close()

    # id и created_at намеренно не экспортируются — это внутренние
    # значения конкретной установки, при импорте на другую (или в ту же
    # после повторного экспорта) они всё равно не имеют смысла;
    # сопоставление при импорте идёт по имени сервера, единственному
    # человекочитаемому и переносимому идентификатору.
    data = [dict(s) for s in servers]
    payload = json.dumps(data, ensure_ascii=False, indent=2)

    response = make_response(payload)
    response.headers["Content-Type"] = "application/json; charset=utf-8"
    response.headers["Content-Disposition"] = (
        "attachment; filename=trassir-monitor-servers-"
        + datetime.now().strftime("%Y%m%d_%H%M%S") + ".json"
    )
    return response


@app.route("/api/servers/import", methods=["POST"])
def import_servers():
    """
    Импорт серверов из файла в формате /api/servers/export (или
    составленного вручную по тому же образцу).

    Сопоставление с уже существующими серверами — по НАЗВАНИЮ: оно
    единственное человекочитаемое и не завязано на id конкретной БД
    (id новой установки неизбежно не совпадут со старыми). Совпало имя —
    обновляем запись, не совпало — добавляем новую. Пустой sdk_password
    в импортируемой записи не затирает уже сохранённый пароль — та же
    логика "пустое поле = оставить как есть", что и в обычном
    PUT /api/servers, на случай если файл экспорта отредактировали
    вручную и забыли про пароль (или намеренно вычистили его перед
    тем, как поделиться файлом с кем-то ещё).
    """
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403

    try:
        data = request.get_json(force=True, silent=False)
    except Exception:
        return jsonify({"ok": 0, "error": "Не удалось разобрать JSON"}), 400

    if not isinstance(data, list):
        return jsonify({"ok": 0, "error": "Ожидался список серверов (JSON-массив)"}), 400

    if len(data) > 500:
        return jsonify({"ok": 0, "error": "Слишком много записей за один импорт (максимум 500)"}), 400

    conn = get_db()
    added = 0
    updated = 0
    errors = []

    for i, entry in enumerate(data):
        if not isinstance(entry, dict):
            errors.append(f"Запись {i + 1}: не объект")
            continue

        name = str(entry.get("name", "")).strip()
        ip = str(entry.get("ip", "")).strip()
        if not name or not ip:
            errors.append(f"Запись {i + 1}: не указано название или IP")
            continue

        try:
            port = int(entry.get("port", 8080))
        except (TypeError, ValueError):
            errors.append(f"Запись {i + 1} ({name}): некорректный порт")
            continue

        ssl_val = bool(entry.get("ssl", True))
        enabled_val = bool(entry.get("enabled", True))
        sdk_password = str(entry.get("sdk_password") or "")

        existing = conn.execute(
            "SELECT id FROM servers WHERE name = ?", (name,)
        ).fetchone()

        if existing:
            if sdk_password:
                conn.execute(
                    "UPDATE servers SET ip = ?, port = ?, sdk_password = ?, ssl = ?, enabled = ? WHERE id = ?",
                    (ip, port, sdk_password, ssl_val, enabled_val, existing["id"])
                )
            else:
                conn.execute(
                    "UPDATE servers SET ip = ?, port = ?, ssl = ?, enabled = ? WHERE id = ?",
                    (ip, port, ssl_val, enabled_val, existing["id"])
                )
            updated += 1
        else:
            conn.execute(
                "INSERT INTO servers (name, ip, port, sdk_password, ssl, enabled) VALUES (?, ?, ?, ?, ?, ?)",
                (name, ip, port, sdk_password, ssl_val, enabled_val)
            )
            added += 1

    conn.commit()
    conn.close()

    if added or updated:
        threading.Thread(target=collect).start()

    return jsonify({"ok": 1, "added": added, "updated": updated, "errors": errors})


@app.route("/api/ack/<int:server_id>", methods=["POST"])
@app.route("/api/alerts/<int:server_id>/ack", methods=["POST"])
def acknowledge_alerts(server_id):
    """
    API: подтвердить (сбросить) все активные алерты для сервера.
    """
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403

    conn = get_db()
    conn.execute(
        "UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours') WHERE server_id = ? AND ack = 0",
        (server_id,)
    )
    conn.commit()
    conn.close()
    
    return jsonify({"ok": 1, "message": "Алерты подтверждены"})


@app.route("/api/alerts/<int:alert_id>/dismiss", methods=["POST"])
def dismiss_alert(alert_id):
    """
    API: подтвердить (сбросить) ОДИН конкретный алерт по его id.

    Раньше единственным способом закрыть алерт вручную было "Сбросить
    все" для всего сервера — если один конкретный алерт не закрывается
    автоматически (например, камера была переименована/удалена в
    TRASSIR и её больше нет в списке под старым именем, поэтому автомат
    не может сопоставить "восстановилась" с "не существует"), сброс
    только его означал попутно сбросить и все остальные, ещё
    действительно активные проблемы того же сервера.
    """
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403

    conn = get_db()
    conn.execute(
        "UPDATE alerts SET ack = 1, resolved_at = datetime('now', '+3 hours') WHERE id = ? AND ack = 0",
        (alert_id,)
    )
    conn.commit()
    conn.close()

    return jsonify({"ok": 1, "message": "Алерт подтверждён"})


@app.route("/api/settings", methods=["GET", "POST"])
def api_settings():
    conn = get_db()
    
    if request.method == "GET":
        settings_dict = dict(conn.execute("SELECT key, value FROM settings").fetchall())
        conn.close()
        # Хеш пароля никогда не должен покидать сервер, даже авторизованным
        # клиентам — фронтенду он не нужен ни для чего.
        settings_dict.pop("admin_password", None)
        return jsonify(settings_dict)

    if not session.get("logged_in"):
        conn.close()
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403

    elif request.method == "POST":
        data = request.json or {}
        for key, value in data.items():
            if key == "admin_password":
                value = generate_password_hash(str(value))
            else:
                value = str(value)
            conn.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                (key, value)
            )
        conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Настройки сохранены"})


@app.route("/api/version/check")
def check_version():
    """
    "Проверить обновления" — сравнивает коммит, зафиксированный при
    установке/обновлении КАЖДОГО реально установленного модуля (см.
    _read_installed_commit), с текущим HEAD ветки main на GitHub.
    Единственный источник правды о "текущей" версии здесь — реальный
    запрос к GitHub прямо сейчас, а не что-то закешированное: этот
    проект не хранит нигде отдельно "какая версия сейчас самая
    новая" — она попросту равна тому, что лежит в main в момент вызова.

    Модуль считается неустановленным (и не попадает в ответ), если для
    него ещё никогда не фиксировался коммит — то есть либо он реально
    не установлен, либо установлен версией до появления этой фичи
    (тогда ответ будет "?" для installed, что тоже показывается как
    "не удалось определить", а не как "нужно обновление" — путать
    "не знаем" с "устарело" было бы хуже, чем оставить как есть).
    """
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403

    try:
        r = requests.get(
            "https://api.github.com/repos/naumenis-code/TRASSIR-Monitor/commits/main",
            headers={"Accept": "application/vnd.github+json"},
            timeout=10
        )
        r.raise_for_status()
        latest_commit = r.json()["sha"][:7]
    except Exception as e:
        return jsonify({"ok": 0, "error": f"Не удалось обратиться к GitHub: {e}"}), 502

    modules = {}
    for module, label in (("dashboard", "Дашборд"), ("telegram", "Telegram"), ("mail", "Email")):
        installed = _read_installed_commit(module)
        if installed == "?":
            continue
        modules[module] = {
            "label": label,
            "installed": installed,
            "up_to_date": installed == latest_commit
        }

    return jsonify({"ok": 1, "latest_commit": latest_commit, "modules": modules})


@app.route("/api/telegram/chats", methods=["GET", "POST", "PUT", "DELETE"])
def api_telegram_chats():
    conn = get_db()
    if request.method == "GET":
        try:
            chats = [dict(r) for r in conn.execute("SELECT * FROM telegram_chats ORDER BY id").fetchall()]
        except Exception:
            chats = []
        conn.close()
        return jsonify(chats)
    if not session.get("logged_in"):
        conn.close()
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403
    data = {}
    if request.content_type and "application/json" in request.content_type:
        data = request.get_json(silent=True) or {}
    if request.method == "POST":
        chat_id = str(data.get("chat_id", "")).strip()
        name    = data.get("name", "").strip()
        if not chat_id:
            conn.close()
            return jsonify({"ok": 0, "error": "chat_id обязателен"}), 400
        conn.execute("INSERT OR IGNORE INTO telegram_chats (chat_id, name) VALUES (?, ?)", (chat_id, name))
        conn.commit()
        conn.close()
        return jsonify({"ok": 1})
    elif request.method == "PUT":
        cid = data.get("id")
        if "enabled" in data and len(data) == 2:
            # Только toggle enabled
            conn.execute("UPDATE telegram_chats SET enabled=? WHERE id=?", (data.get("enabled"), cid))
        else:
            conn.execute("UPDATE telegram_chats SET chat_id=?, name=?, enabled=?, warning=?, critical=? WHERE id=?",
                (data.get("chat_id"), data.get("name",""), data.get("enabled",1),
                 data.get("warning",1), data.get("critical",1), cid))
        conn.commit()
        conn.close()
        return jsonify({"ok": 1})
    elif request.method == "DELETE":
        cid = request.args.get("id")
        conn.execute("DELETE FROM telegram_chats WHERE id=?", (cid,))
        conn.commit()
        conn.close()
        return jsonify({"ok": 1})
    conn.close()
    return jsonify({"ok": 0}), 400


def _mask_secret_url(url):
    """Маскирует логин:пароль внутри URL (scheme://user:pass@host) перед показом в UI —
    тот же приём, что и sed-маскировка в install-telegram-notifier.sh при вводе прокси."""
    return re.sub(r'(://[^:@/\s]+:)([^@\s]+)(@)', r'\1***\3', url or "")


@app.route("/api/telegram/settings", methods=["GET", "POST"])
def api_telegram_settings():
    conn = get_db()
    if request.method == "GET":
        # Базовый статус доступен всем — только факт настройки без деталей
        import configparser as _cp, os as _os
        result = {"token_configured": False, "proxy_url": "", "token_masked": ""}
        for cfg_file in ["config_tgproxy.ini", "config.ini"]:
            cfg_path = os.path.join(BASE_DIR, cfg_file)
            if _os.path.exists(cfg_path):
                cfg = _cp.ConfigParser()
                cfg.read(cfg_path)
                if "telegram" in cfg:
                    token = cfg["telegram"].get("token", "").strip()
                    if token:
                        result["token_configured"] = True
                        result["token_masked"] = token[:10] + "..." + token[-4:]
                    result["proxy_url"] = cfg["telegram"].get("proxy_url", "").strip()
                    ini_proxy = cfg["telegram"].get("proxy", "").strip()
                    result["proxy_configured"] = bool(ini_proxy)
                    result["proxy_masked"] = _mask_secret_url(ini_proxy)
                    break
        # Настройки из БД — только для авторизованных. Способ отправки
        # (proxy_url/api_base/api_key) можно менять здесь без переустановки
        # бота — tg_bot.py перечитывает эти три ключа из той же БД на
        # каждую отправку (см. get_db_transport_overrides() в tg_bot.py).
        # proxy_url и api_key могут нести секрет (логин:пароль прокси,
        # ключ доступа к relay) — как и token выше, наружу отдаём только
        # факт настройки + маскированное значение, никогда сырое (форма
        # в settings.html трактует пустое поле как "не менять", как и с
        # паролем администратора/серверов).
        if session.get("logged_in"):
            try:
                s = dict(conn.execute("SELECT key, value FROM telegram_settings").fetchall())
                raw_proxy_url = s.pop("proxy_url", "")
                raw_api_key = s.pop("api_key", "")
                result.update(s)
                result["proxy_url_configured"] = bool(raw_proxy_url)
                result["proxy_url_masked"] = _mask_secret_url(raw_proxy_url)
                result["api_key_configured"] = bool(raw_api_key)
                result["api_key_masked"] = (raw_api_key[:4] + "..." + raw_api_key[-4:]) if len(raw_api_key) > 8 else ("***" if raw_api_key else "")
            except Exception:
                pass
        conn.close()
        return jsonify(result)
    if not session.get("logged_in"):
        conn.close()
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403
    data = request.json or {}
    proxy_url = str(data.get("proxy_url", "")).strip()
    if proxy_url and not re.match(r'^(https?|socks5h?)://', proxy_url, re.IGNORECASE):
        conn.close()
        return jsonify({"ok": 0, "error": "Прокси должен начинаться с http://, https://, socks5:// или socks5h://"}), 400
    api_base = str(data.get("api_base", "")).strip()
    if api_base and not re.match(r'^https?://', api_base, re.IGNORECASE):
        conn.close()
        return jsonify({"ok": 0, "error": "Адрес своего API (workers/relay) должен начинаться с http:// или https://"}), 400
    for key, value in data.items():
        conn.execute("INSERT OR REPLACE INTO telegram_settings (key, value) VALUES (?, ?)", (key, str(value)))
    conn.commit()
    conn.close()
    return jsonify({"ok": 1})


@app.route("/api/telegram/test", methods=["POST"])
def api_telegram_test():
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403
    import importlib, sys
    try:
        if "app.tg_proxy_bot" in sys.modules:
            mod = sys.modules["app.tg_proxy_bot"]
        elif "app.tg_bot" in sys.modules:
            mod = sys.modules["app.tg_bot"]
        elif os.path.exists(os.path.join(BASE_DIR, "app", "tg_proxy_bot.py")):
            sys.path.insert(0, BASE_DIR)
            mod = importlib.import_module("app.tg_proxy_bot")
        elif os.path.exists(os.path.join(BASE_DIR, "app", "tg_bot.py")):
            sys.path.insert(0, BASE_DIR)
            mod = importlib.import_module("app.tg_bot")
        else:
            return jsonify({"ok": 0, "error": "Telegram бот не установлен"}), 400
        chats = mod.get_enabled_chats()
        if not chats:
            return jsonify({"ok": 0, "error": "Нет активных получателей"}), 400
        cfg = mod.get_config()
        monitor_url = cfg.get("monitor_url", "") if cfg else ""
        msg = mod.format_test_message(monitor_url)
        ok = mod.send_telegram_message(chats[0]["chat_id"], msg)
        return jsonify({"ok": 1 if ok else 0})
    except Exception as e:
        return jsonify({"ok": 0, "error": str(e)}), 500


@app.route("/api/mail/recipients", methods=["GET", "POST", "PUT", "DELETE"])
def api_mail_recipients():
    conn = get_db()
    if request.method == "GET":
        try:
            rows = [dict(r) for r in conn.execute("SELECT * FROM mail_recipients ORDER BY id").fetchall()]
        except Exception:
            rows = []
        conn.close()
        return jsonify(rows)
    if not session.get("logged_in"):
        conn.close()
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403
    data = {}
    if request.content_type and "application/json" in request.content_type:
        data = request.get_json(silent=True) or {}
    if request.method == "POST":
        email = data.get("email", "").strip()
        if not email or "@" not in email:
            conn.close()
            return jsonify({"ok": 0, "error": "Некорректный email"}), 400
        conn.execute("INSERT OR IGNORE INTO mail_recipients (email, name) VALUES (?, ?)",
                     (email, data.get("name", "").strip()))
        conn.commit()
        conn.close()
        return jsonify({"ok": 1})
    elif request.method == "PUT":
        if "enabled" in data and len(data) == 2:
            conn.execute("UPDATE mail_recipients SET enabled=? WHERE id=?",
                (data.get("enabled"), data.get("id")))
        else:
            conn.execute("UPDATE mail_recipients SET email=?, name=?, enabled=? WHERE id=?",
                (data.get("email"), data.get("name",""), data.get("enabled",1), data.get("id")))
        conn.commit()
        conn.close()
        return jsonify({"ok": 1})
    elif request.method == "DELETE":
        conn.execute("DELETE FROM mail_recipients WHERE id=?", (request.args.get("id"),))
        conn.commit()
        conn.close()
        return jsonify({"ok": 1})
    conn.close()
    return jsonify({"ok": 0}), 400


@app.route("/api/mail/settings", methods=["GET", "POST"])
def api_mail_settings():
    conn = get_db()
    if request.method == "GET":
        try:
            s = dict(conn.execute("SELECT key, value FROM mail_settings").fetchall())
            s["smtp_configured"] = bool(s.get("smtp_server", "").strip())
            # Пароль только для авторизованных
            if not session.get("logged_in"):
                s.pop("smtp_pass", None)
                s.pop("smtp_user", None)
            else:
                if s.get("smtp_pass"):
                    s["smtp_pass_masked"] = "\u2022" * 8
                s.pop("smtp_pass", None)
        except Exception:
            s = {"smtp_configured": False}
        conn.close()
        return jsonify(s)
    if not session.get("logged_in"):
        conn.close()
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403
    data = request.json or {}
    for key, value in data.items():
        conn.execute("INSERT OR REPLACE INTO mail_settings (key, value) VALUES (?, ?)", (key, str(value)))
    conn.commit()
    conn.close()
    return jsonify({"ok": 1})


@app.route("/api/mail/test", methods=["POST"])
def api_mail_test():
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403
    import importlib, sys
    try:
        if os.path.exists(os.path.join(BASE_DIR, "app", "mail_bot.py")):
            sys.path.insert(0, BASE_DIR)
            mod = importlib.import_module("app.mail_bot")
            recipients = mod.get_enabled_recipients()
            if not recipients:
                return jsonify({"ok": 0, "error": "Нет активных получателей"}), 400
            conn = get_db()
            s = dict(conn.execute("SELECT key, value FROM mail_settings").fetchall())
            conn.close()
            ok = mod.send_email(recipients[0]["email"], recipients[0].get("name",""),
                                "Тест TRASSIR Monitor", "<p>Тестовое сообщение</p>", s)
            return jsonify({"ok": 1 if ok else 0})
        return jsonify({"ok": 0, "error": "Mail бот не установлен"}), 400
    except Exception as e:
        return jsonify({"ok": 0, "error": str(e)}), 500


@app.route("/test-connection", methods=["POST"])
def test_connection():
    """
    API: проверить подключение к серверу TRASSIR.
    Используется кнопкой "Проверить" в форме добавления сервера.
    """
    if not session.get("logged_in"):
        return jsonify({"ok": 0, "error": "Требуется авторизация"}), 403

    data = request.json

    client = TrassirClient({
        "ip": data.get("ip"),
        "port": data.get("port", 8080),
        "ssl": data.get("ssl", True),
        "sdk_password": data.get("sdk_password", "")
    })
    
    result = client.get()
    
    return jsonify({
        "success": result["ok"] == 1,
        "response_time_ms": result.get("rt"),
        "data": {
            "cpu": result.get("cpu"),
            "channels_total": result.get("ch_t"),
            "channels_online": result.get("ch_o"),
            "archive_days": result.get("arch")
        },
        "error": result.get("err")
    })



# ============================================
# ВСПОМОГАТЕЛЬНЫЙ API — статус служб
# ============================================

@app.route("/api/services/status")
def api_services_status():
    """Возвращает статус установленных нотифайеров."""
    import os as _os
    return jsonify({
        "telegram": _os.path.exists(os.path.join(BASE_DIR, "app", "tg_bot.py")) or
                    _os.path.exists(os.path.join(BASE_DIR, "app", "tg_proxy_bot.py")),
        "mail":     _os.path.exists(os.path.join(BASE_DIR, "app", "mail_bot.py")),
        "telegram_proxy": _os.path.exists(os.path.join(BASE_DIR, "app", "tg_proxy_bot.py")),
    })

if __name__ != "__main__":
    # Вывод при запуске через gunicorn
    print("=" * 60)
    print("  TRASSIR Monitor v13.0")
    print("  Система мониторинга серверов TRASSIR")
    print("=" * 60)

# Инициализируем базу данных
init_db()

# Запускаем планировщик в фоновом потоке
scheduler_thread = threading.Thread(target=scheduler, daemon=True)
scheduler_thread.start()

print("Приложение готово к работе!")
APPEOF

echo "  • Файл app.py создан"
echo "  • Размер файла: $(wc -c < $INSTALL_DIR/app/app.py) байт"
echo "  • Количество строк: $(wc -l < $INSTALL_DIR/app/app.py)"
echo ""

# Проверка синтаксиса Python
echo "  • Проверка синтаксиса Python..."
source $INSTALL_DIR/venv/bin/activate
python3 -c "import ast; ast.parse(open('$INSTALL_DIR/app/app.py').read()); print('    ✓ Синтаксис корректен')" || {
    echo "    ❌ Ошибка синтаксиса!"
    exit 1
}
deactivate

echo ""
echo -e "${GREEN}✅ Приложение создано${NC}"
echo ""

# ============================================
# ШАГ 5: СОЗДАНИЕ HTML ШАБЛОНОВ
# ============================================
echo -e "${YELLOW}[5/7] Создание HTML шаблонов...${NC}"
echo ""

# Скачиваем все внешние ресурсы локально для работы без интернета
echo "  • Скачивание статических ресурсов..."

mkdir -p $INSTALL_DIR/static/fonts

# _DL_FAILED собирает имена файлов, которые не удалось ни найти на
# месте (восстановленными с прошлой установки), ни скачать — печатается
# отдельным заметным предупреждением в конце этого шага (см. ниже).
_DL_FAILED=()

_dl() {
    local url="$1" dest="$2" name="$3"
    # Уже есть валидный файл — либо восстановлен на ШАГе 3 (обновление),
    # либо остался от прерванного повторного запуска. Не перекачиваем:
    # именно это делает обновление в сети без интернета безопасным —
    # единственный раз, когда эти файлы обязаны быть реально скачаны,
    # это самая первая установка.
    if [ -s "$dest" ]; then
        echo "    ✓ $name — уже на месте ($(wc -c < "$dest") байт)"
        return 0
    fi
    if curl -sL --connect-timeout 15 --retry 3 --retry-delay 2 -o "$dest" "$url" 2>/dev/null && [ -s "$dest" ]; then
        echo "    ✓ $name ($(wc -c < "$dest") байт)"
    else
        echo "    ⚠ Не удалось скачать $name"
        rm -f "$dest"
        _DL_FAILED+=("$name")
    fi
}

_dl "https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.5.0/socket.io.min.js" \
    "$INSTALL_DIR/static/socket.io.min.js" "socket.io"

_dl "https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" \
    "$INSTALL_DIR/static/bootstrap.min.css" "bootstrap.css"

_dl "https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js" \
    "$INSTALL_DIR/static/bootstrap.bundle.min.js" "bootstrap.js"

_dl "https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js" \
    "$INSTALL_DIR/static/chart.min.js" "chart.js"

# Bootstrap Icons — CSS + шрифты
_dl "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.0/font/bootstrap-icons.css" \
    "$INSTALL_DIR/static/bootstrap-icons.css" "bootstrap-icons.css"

_dl "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.0/font/fonts/bootstrap-icons.woff2" \
    "$INSTALL_DIR/static/fonts/bootstrap-icons.woff2" "bootstrap-icons.woff2"

_dl "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.8.0/font/fonts/bootstrap-icons.woff" \
    "$INSTALL_DIR/static/fonts/bootstrap-icons.woff" "bootstrap-icons.woff"

# Пересоздаём @font-face в начале CSS с правильными локальными путями
# (оригинальный CSS может использовать ../fonts/ или другие относительные пути)
if [ -f "$INSTALL_DIR/static/bootstrap-icons.css" ]; then
    # Удаляем существующий @font-face блок и вставляем правильный
    awk '
        /^@font-face/ { skip=1 }
        skip && /\}/ { skip=0; next }
        !skip { print }
    ' "$INSTALL_DIR/static/bootstrap-icons.css" > /tmp/bi_clean.css

    cat > "$INSTALL_DIR/static/bootstrap-icons.css" << 'FONTEOF'
@font-face {
  font-family: "bootstrap-icons";
  src: url("/static/fonts/bootstrap-icons.woff2") format("woff2"),
       url("/static/fonts/bootstrap-icons.woff") format("woff");
}
FONTEOF
    cat /tmp/bi_clean.css >> "$INSTALL_DIR/static/bootstrap-icons.css"
    rm -f /tmp/bi_clean.css
    echo "    ✓ @font-face обновлён → /static/fonts/"
fi

# Дашборд ссылается ТОЛЬКО на локальные /static/... пути (никаких CDN
# в самих шаблонах — см. CLAUDE.md "Готовность к автономной сети"), но
# это защищает только от обращений к интернету НА КАЖДОЙ загрузке
# страницы. Если хоть один из файлов выше так и не появился на диске
# (первая установка без интернета либо интернет пропал посреди неё),
# дашборд у реальных пользователей будет открываться без стилей/иконок/
# графиков/live-обновления молча — без этого предупреждения это было бы
# видно только тем, кто внимательно читает вывод установщика.
if [ ${#_DL_FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}⚠️  ВНИМАНИЕ: не удалось получить ${#_DL_FAILED[@]} файл(ов), нужных для автономной работы:${NC}"
    for _f in "${_DL_FAILED[@]}"; do
        echo -e "${RED}    ✗ $_f${NC}"
    done
    echo -e "${YELLOW}   Дашборд запустится, но без этих файлов часть интерфейса не будет${NC}"
    echo -e "${YELLOW}   работать (стили, графики, иконки или live-обновления через WebSocket).${NC}"
    echo -e "${YELLOW}   Сам дашборд НИКОГДА не обращается к внешним CDN сам по себе — только${NC}"
    echo -e "${YELLOW}   к $INSTALL_DIR/static/, поэтому единственный способ починить это —${NC}"
    echo -e "${YELLOW}   запустить установку заново при рабочем интернете (уже скачанные${NC}"
    echo -e "${YELLOW}   файлы не перекачиваются повторно, поэтому это безопасно и быстро).${NC}"
    echo ""
fi

# ---------- base.html ----------
echo ""
echo "  • Создание base.html..."
cat > $INSTALL_DIR/templates/base.html << 'BASEEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    
    <!-- Favicon -->
    <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 16 16%22><text y=%2214%22 font-size=%2214%22>📹</text></svg>">
    
    <title>{% block title %}TRASSIR Monitor{% endblock %}</title>
    
    <!-- Bootstrap 5 CSS (локальный) -->
    <link href="/static/bootstrap.min.css" rel="stylesheet">
    
    <!-- Bootstrap Icons (локальный) -->
    <link href="/static/bootstrap-icons.css" rel="stylesheet">
    
    <!-- Chart.js для графиков (локальный) -->
    <script src="/static/chart.min.js"></script>
    
    <!-- Socket.io (локальный) -->
    <script src="/static/socket.io.min.js"></script>
    
    <style>
        /* ============================================ */
        /* ЦВЕТОВАЯ СХЕМА (ТЁМНАЯ ТЕМА)                 */
        /* ============================================ */
        :root {
            --bg: #0a0d14;
            --card: #141820;
            --border: #252b36;
            --acc: #667eea;
            --txt: #d1d5db;
            --muted: #6b7280;
            --green: #10b981;
            --yellow: #f59e0b;
            --red: #ef4444;
        }
        
        /* ============================================ */
        /* БАЗОВЫЕ СТИЛИ                                 */
        /* ============================================ */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            background: var(--bg);
            color: var(--txt);
            font-family: 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            min-height: 100vh;
        }
        
        /* ============================================ */
        /* НАВИГАЦИЯ                                     */
        /* ============================================ */
        .navbar {
            background: var(--card) !important;
            border-bottom: 2px solid var(--border);
            padding: 12px 0;
        }
        
        .navbar-brand {
            font-size: 1.3rem;
            font-weight: 700;
            color: #fff !important;
        }
        
        .navbar-brand i {
            color: var(--acc);
            margin-right: 8px;
        }
        
        /* ============================================ */
        /* КАРТОЧКИ                                       */
        /* ============================================ */
        .card {
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: 16px;
            margin-bottom: 20px;
        }
        
        .card-header {
            background: rgba(102, 126, 234, 0.05);
            border-bottom: 1px solid var(--border);
            padding: 16px 24px;
            font-weight: 600;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .card-body {
            padding: 24px;
        }
        
        /* ============================================ */
        /* СТАТИСТИЧЕСКИЕ КАРТОЧКИ                       */
        /* ============================================ */
        .stat-card {
            border-radius: 16px;
            padding: 24px;
            text-align: center;
            color: #fff;
            position: relative;
            overflow: hidden;
            transition: all 0.3s;
        }
        
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
        }
        
        .stat-card.primary {
            background: linear-gradient(135deg, #667eea, #764ba2);
        }
        .stat-card.primary::before {
            background: linear-gradient(90deg, #667eea, #764ba2);
        }
        
        .stat-card.success {
            background: linear-gradient(135deg, #059669, #10b981);
        }
        .stat-card.success::before {
            background: linear-gradient(90deg, #059669, #10b981);
        }
        
        .stat-card.warning {
            background: linear-gradient(135deg, #d97706, #f59e0b);
        }
        .stat-card.warning::before {
            background: linear-gradient(90deg, #d97706, #f59e0b);
        }
        
        .stat-card.danger {
            background: linear-gradient(135deg, #dc2626, #ef4444);
        }
        .stat-card.danger::before {
            background: linear-gradient(90deg, #dc2626, #ef4444);
        }
        
        .stat-card:hover {
            transform: translateY(-3px);
        }
        
        .stat-value {
            font-size: 2.5rem;
            font-weight: 800;
            margin: 8px 0;
        }
        
        .stat-label {
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 2px;
            opacity: 0.7;
        }
        
        /* ============================================ */
        /* СТРОКА СЕРВЕРА                                 */
        /* ============================================ */
        .server-row {
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: 12px;
            margin-bottom: 12px;
            padding: 20px;
            transition: all 0.3s;
        }
        
        .server-row:hover {
            border-color: var(--acc);
            box-shadow: 0 4px 20px rgba(102, 126, 234, 0.2);
        }
        
        /* ============================================ */
        /* ИНДИКАТОРЫ СТАТУСА                             */
        /* ============================================ */
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            display: inline-block;
            margin-right: 10px;
        }
        
        .status-dot.online {
            background: var(--green);
            box-shadow: 0 0 12px rgba(16, 185, 129, 0.5);
        }
        
        .status-dot.warning {
            background: var(--yellow);
            box-shadow: 0 0 12px rgba(245, 158, 11, 0.5);
        }
        
        .status-dot.offline {
            background: var(--red);
            box-shadow: 0 0 12px rgba(239, 68, 68, 0.5);
            animation: blink 1.5s infinite;
        }
        
        @keyframes blink {
            50% { opacity: 0.3; }
        }
        
        /* ============================================ */
        /* МЕТРИКИ                                        */
        /* ============================================ */
        .metric-label {
            font-size: 0.7rem;
            color: var(--muted);
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 4px;
        }
        
        .metric-value {
            font-size: 1.1rem;
            font-weight: 600;
        }
        
        /* ============================================ */
        /* ГРАФИКИ                                        */
        /* ============================================ */
        .chart-container {
            position: relative;
            height: 350px;
        }
        
        /* ============================================ */
        /* LIVE ИНДИКАТОР                                 */
        /* ============================================ */
        .live-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            background: var(--green);
            border-radius: 50%;
            margin-right: 8px;
            animation: livePulse 1.5s infinite;
        }
        
        @keyframes livePulse {
            0%, 100% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7); }
            50% { box-shadow: 0 0 0 10px rgba(16, 185, 129, 0); }
        }
        
        /* ============================================ */
        /* ФОРМЫ                                          */
        /* ============================================ */
        .form-control, .form-select {
            background: var(--bg) !important;
            border: 1px solid var(--border) !important;
            color: var(--txt) !important;
            border-radius: 8px;
            padding: 10px 14px;
        }
        
        .form-control:focus, .form-select:focus {
            background: var(--bg) !important;
            border-color: var(--acc) !important;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.2) !important;
            color: #fff !important;
        }

        .form-control::placeholder {
            color: var(--muted) !important;
            opacity: 1 !important;
        }

        /* Автозаполнение браузера — тёмный фон */
        .form-control:-webkit-autofill,
        .form-control:-webkit-autofill:hover,
        .form-control:-webkit-autofill:focus {
            -webkit-text-fill-color: var(--txt) !important;
            -webkit-box-shadow: 0 0 0px 1000px var(--bg) inset !important;
            transition: background-color 5000s ease-in-out 0s;
        }

        /* Таблицы */
        .table-dark {
            --bs-table-bg: var(--card);
            --bs-table-color: var(--txt);
        }
        
        /* ============================================ */
        /* МОДАЛЬНЫЕ ОКНА                                 */
        /* ============================================ */
        .modal-content {
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: 16px;
        }
        
        .modal-content .form-control,
        .modal-content .form-select {
            background: #1a1d27 !important;
            border: 1px solid #2d3239 !important;
            color: #e1e1e1 !important;
        }
        
        .modal-header {
            border-bottom: 1px solid var(--border);
        }
        
        /* ============================================ */
        /* КНОПКИ                                         */
        /* ============================================ */
        .btn {
            border-radius: 8px;
            padding: 8px 16px;
            font-weight: 500;
        }
        
        .btn-primary {
            background: var(--acc);
            border-color: var(--acc);
        }
        
        .btn-primary:hover {
            background: #5a6fd6;
        }
        
        /* ============================================ */
        /* АЛЕРТЫ                                         */
        /* ============================================ */
        .alert-item {
            padding: 16px 20px;
            margin-bottom: 12px;
            border-radius: 12px;
            border-left: 6px solid;
            font-size: 0.95rem;
        }
        
        .alert-item.critical {
            background: rgba(239, 68, 68, 0.2);
            border-color: #ef4444;
            box-shadow: 0 0 20px rgba(239, 68, 68, 0.3);
            color: #fca5a5;
        }
        
        .alert-item.warning {
            background: rgba(245, 158, 11, 0.2);
            border-color: #f59e0b;
            box-shadow: 0 0 20px rgba(245, 158, 11, 0.3);
            color: #fcd34d;
        }
        
        .alert-item.info {
            background: rgba(16, 185, 129, 0.15);
            border-color: #10b981;
            box-shadow: 0 0 15px rgba(16, 185, 129, 0.2);
            color: #6ee7b7;
        }
        
        /* ============================================ */
        /* СКРОЛЛБАР                                      */
        /* ============================================ */
        ::-webkit-scrollbar {
            width: 6px;
        }
        
        ::-webkit-scrollbar-track {
            background: var(--bg);
        }
        
        ::-webkit-scrollbar-thumb {
            background: var(--border);
            border-radius: 3px;
        }
        
        /* ============================================ */
        /* АДАПТИВНОСТЬ                                   */
        /* ============================================ */
        @media (max-width: 768px) {
            .stat-value {
                font-size: 1.8rem;
            }
            .server-row {
                padding: 14px;
            }
        }
    </style>
</head>
<body>
    <!-- Навигационная панель -->
    <nav class="navbar navbar-dark">
        <div class="container">
            <a class="navbar-brand" href="/">
                <i class="bi bi-camera-video-fill"></i>TRASSIR Monitor
            </a>
            <span class="navbar-text">
                <span class="live-indicator"></span>
                <span id="clock"></span>
            </span>
            <div class="d-flex gap-2 ms-3">
                <a href="/settings" class="btn btn-outline-light btn-sm" title="Настройки">
                    <i class="bi bi-gear"></i>
                </a>
                {% if logged_in %}
                <a href="/logout" class="btn btn-outline-warning btn-sm" title="Выйти">
                    <i class="bi bi-box-arrow-right"></i> Выйти
                </a>
                {% else %}
                <a href="/login" class="btn btn-outline-success btn-sm" title="Войти">
                    <i class="bi bi-box-arrow-in-right"></i> Войти
                </a>
                {% endif %}
            </div>
        </div>
    </nav>
    
    <!-- Основной контент -->
    <div class="container mt-4">
        {% block content %}{% endblock %}
    </div>

    {% block footer %}{% endblock %}

    <!-- Bootstrap JS (локальный) -->
    <script src="/static/bootstrap.bundle.min.js"></script>

    <!-- Скрипты -->
    <script>
        // Экранирование пользовательских строк перед вставкой через innerHTML —
        // имя получателя Telegram/Email, SMTP-логин и т.п. приходят из API как
        // обычные строки и могли бы разорвать HTML/атрибут при вставке как есть
        // (см. renderTelegram()/renderMail() в settings.html).
        function escapeHtml(value) {
            if (value === null || value === undefined) return '';
            return String(value).replace(/[&<>"']/g, function(c) {
                return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
            });
        }

        // Часы в навигации
        setInterval(function() {
            document.getElementById('clock').textContent = new Date().toLocaleString('ru-RU');
        }, 1000);

        // WebSocket подключение
        const socket = io();
        
        socket.on('connect', function() {
            console.log('WebSocket подключён');
        });
        
        socket.on('update', function(data) {
            if (typeof window.handleUpdate === 'function') {
                window.handleUpdate(data);
            }
        });
    </script>
    
    {% block scripts %}{% endblock %}
</body>
</html>
BASEEOF
echo "    ✓ base.html создан ($(wc -c < $INSTALL_DIR/templates/base.html) байт)"

# ---------- dashboard.html ----------
echo "  • Создание dashboard.html..."
cat > $INSTALL_DIR/templates/dashboard.html << 'DASHEOF'
{% extends "base.html" %}

{% block title %}TRASSIR Monitor — Дашборд{% endblock %}

{% block content %}

<!-- ============================================ -->
<!-- СТАТИСТИЧЕСКИЕ КАРТОЧКИ                      -->
<!-- ============================================ -->
<div class="row g-3 mb-4">
    <!-- Количество серверов -->
    <div class="col-md-3">
        <div class="stat-card primary">
            <div class="stat-label">Серверов</div>
            <div class="stat-value" id="statServers">{{ stats.total_servers }}</div>
        </div>
    </div>
    
    <!-- Камер онлайн -->
    <div class="col-md-3">
        <div class="stat-card success">
            <div class="stat-label">Камер онлайн</div>
            <div class="stat-value" id="statOnline">{{ stats.online_cameras }}</div>
        </div>
    </div>
    
    <!-- Офлайн камер -->
    <div class="col-md-3">
        <div class="stat-card warning">
            <div class="stat-label">Офлайн камер</div>
            <div class="stat-value" id="statOffline">{{ stats.total_cameras - stats.online_cameras }}</div>
        </div>
    </div>
    
    <!-- Алерты -->
    <div class="col-md-3">
        <div class="stat-card {% if stats.total_alerts > 0 %}danger{% else %}success{% endif %}" id="statAlertsCard">
            <div class="stat-label">Активных алертов</div>
            <div class="stat-value" id="statAlerts">{{ stats.total_alerts }}</div>
        </div>
    </div>
</div>

<!-- ============================================ -->
<!-- СПИСОК СЕРВЕРОВ                               -->
<!-- ============================================ -->
<div class="card">
    <div class="card-header">
        <span>
            <i class="bi bi-hdd-stack"></i> Серверы TRASSIR
        </span>
        {% if logged_in %}
        <button class="btn btn-sm btn-primary" data-bs-toggle="modal" data-bs-target="#addModal">
            <i class="bi bi-plus-lg"></i> Добавить сервер
        </button>
        {% endif %}
    </div>
    <div class="card-body" id="serversList">
        {% if servers %}
            {% for s in servers %}
            <div class="server-row" data-server-id="{{ s.s.id }}">
                <div class="row align-items-center g-2">
                    
                    <!-- Название и IP -->
                    <div class="col-lg-2 col-md-3">
                        <div class="d-flex align-items-center">
                            {% if s.h %}
                                {% if s.h.ch_online == s.h.ch_total %}
                                    <span class="status-dot online"></span>
                                {% elif s.h.ch_online > 0 %}
                                    <span class="status-dot warning"></span>
                                {% else %}
                                    <span class="status-dot offline"></span>
                                {% endif %}
                            {% else %}
                                <span class="status-dot offline"></span>
                            {% endif %}
                            <div>
                                <strong>
                                    <a href="/server/{{ s.s.id }}" style="color: var(--txt); text-decoration: none;">
                                        {{ s.s.name }}
                                    </a>
                                </strong>
                                <br>
                                <small style="color: var(--muted);">{{ s.s.ip }}:{{ s.s.port }}</small>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Камеры -->
                    <div class="col-lg-1 col-md-2 col-4">
                        <div class="metric-label">Камеры</div>
                        <div class="metric-value cams">
                            {{ s.h.ch_online if s.h else '?' }}/{{ s.h.ch_total if s.h else '?' }}
                        </div>
                    </div>
                    
                    <!-- CPU -->
                    <div class="col-lg-1 col-md-2 col-4">
                        <div class="metric-label">CPU</div>
                        <div class="metric-value cpu">
                            {{ "%.1f"|format(s.h.cpu) if s.h else '?' }}%
                        </div>
                    </div>
                    
                    <!-- Диски -->
                    <div class="col-lg-1 col-md-2 col-4">
                        <div class="metric-label">Диски</div>
                        <div class="metric-value disks">
                            {% if s.h %}
                                {% if s.h.disks %}✅{% else %}❌{% endif %}
                            {% else %}?{% endif %}
                        </div>
                    </div>
                    
                    <!-- Архив -->
                    <div class="col-lg-1 col-md-2 col-4">
                        <div class="metric-label">Архив</div>
                        <div class="metric-value arch">
                            {{ "%.1f"|format(s.h.arch) if s.h else '?' }} дн
                        </div>
                    </div>
                    
                    <!-- Uptime -->
                    <div class="col-lg-2 col-md-2 col-4">
                        <div class="metric-label">Uptime</div>
                        <div class="metric-value upt">
                            {% if s.h and s.h.uptime %}
                                {{ (s.h.uptime // 86400)|int }}д {{ ((s.h.uptime % 86400) // 3600)|int }}ч
                            {% else %}?{% endif %}
                        </div>
                    </div>
                    
                    <!-- Время отклика -->
                    <div class="col-lg-1 col-md-2 col-4">
                        <div class="metric-label">Отклик</div>
                        <div class="metric-value rt">
                            {{ s.h.rt if s.h else '?' }}мс
                        </div>
                    </div>
                    
                    <!-- Бейдж алертов -->
                    <div class="col-lg-1 col-md-1 col-4 text-center">
                        {% if s.a > 0 %}
                            <span class="badge bg-danger alerts-badge">{{ s.a }}</span>
                        {% else %}
                            <span class="badge bg-success alerts-badge" style="opacity: 0.3;">0</span>
                        {% endif %}
                    </div>
                    
                    <!-- Кнопки управления -->
                    <div class="col-lg-2 col-md-2 text-end">
                        <a href="/server/{{ s.s.id }}" class="btn btn-sm btn-outline-info">
                            <i class="bi bi-graph-up"></i>
                        </a>
                        {% if logged_in %}
                        <button class="btn btn-sm btn-outline-warning edit-btn"
                                data-id="{{ s.s.id }}"
                                data-name="{{ s.s.name }}"
                                data-ip="{{ s.s.ip }}"
                                data-port="{{ s.s.port }}"
                                data-ssl="{{ s.s.ssl }}">
                            <i class="bi bi-pencil"></i>
                        </button>
                        <button class="btn btn-sm btn-outline-danger" onclick="deleteServer({{ s.s.id }})">
                            <i class="bi bi-trash"></i>
                        </button>
                        {% endif %}
                    </div>
                    
                </div>
            </div>
            {% endfor %}
        {% else %}
            <!-- Нет серверов -->
            <div class="text-center py-5">
                <i class="bi bi-inbox" style="font-size: 4rem; color: var(--muted);"></i>
                <h4 class="mt-3" style="color: var(--muted);">Нет добавленных серверов</h4>
                {% if logged_in %}
                <p style="color: var(--muted);">Добавьте сервер TRASSIR для начала мониторинга</p>
                <button class="btn btn-primary btn-lg mt-3" data-bs-toggle="modal" data-bs-target="#addModal">
                    <i class="bi bi-plus-lg"></i> Добавить сервер
                </button>
                {% else %}
                <p style="color: var(--muted);">Для добавления сервера необходимо
                    <a href="/login">войти</a>.</p>
                {% endif %}
            </div>
        {% endif %}
    </div>
</div>

<!-- ============================================ -->
<!-- ПЛАВАЮЩАЯ КНОПКА ДОБАВЛЕНИЯ                   -->
<!-- ============================================ -->
{% if logged_in %}
<button class="btn btn-primary position-fixed bottom-0 end-0 m-4 rounded-circle shadow-lg"
        style="width: 56px; height: 56px; z-index: 1000;"
        data-bs-toggle="modal" data-bs-target="#addModal"
        title="Добавить сервер">
    <i class="bi bi-plus-lg fs-4"></i>
</button>
{% endif %}

{% if logged_in %}
<!-- ============================================ -->
<!-- МОДАЛЬНОЕ ОКНО: ДОБАВЛЕНИЕ СЕРВЕРА            -->
<!-- ============================================ -->
<div class="modal fade" id="addModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">
                    <i class="bi bi-plus-circle"></i> Добавить сервер TRASSIR
                </h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <form id="addForm">
                    <div class="mb-3">
                        <label class="form-label">Название сервера *</label>
                        <input type="text" class="form-control" name="name" required 
                               placeholder="Например: Главный офис">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">IP адрес *</label>
                        <input type="text" class="form-control" name="ip" required 
                               placeholder="192.168.1.100">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Порт</label>
                        <input type="number" class="form-control" name="port" value="8080">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Тип авторизации</label>
                        <select class="form-select" name="auth_type">
                            <option value="sdk_password">SDK Пароль (рекомендуется)</option>
                            <option value="credentials">Логин и пароль</option>
                        </select>
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">SDK Пароль</label>
                        <input type="password" class="form-control" name="sdk_password" 
                               placeholder="Из настроек TRASSIR: Веб-сервер → Пароль SDK">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Логин</label>
                        <input type="text" class="form-control" name="username" value="admin">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Пароль</label>
                        <input type="password" class="form-control" name="password">
                    </div>
                    
                    <div class="form-check mb-3">
                        <input type="checkbox" class="form-check-input" name="ssl" checked>
                        <label class="form-check-label">Использовать SSL (HTTPS)</label>
                    </div>
                    
                    <div class="d-flex gap-2">
                        <button type="button" class="btn btn-outline-info" onclick="testConnection()">
                            <i class="bi bi-lightning"></i> Проверить подключение
                        </button>
                        <button type="submit" class="btn btn-primary flex-grow-1">
                            <i class="bi bi-plus-lg"></i> Добавить сервер
                        </button>
                    </div>
                    
                    <div id="testResult" class="mt-3" style="display: none;"></div>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- ============================================ -->
<!-- МОДАЛЬНОЕ ОКНО: РЕДАКТИРОВАНИЕ СЕРВЕРА        -->
<!-- ============================================ -->
<div class="modal fade" id="editModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">
                    <i class="bi bi-pencil"></i> Изменить сервер
                </h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <form id="editForm">
                    <input type="hidden" name="id" id="editId">
                    
                    <div class="mb-3">
                        <label class="form-label">Название</label>
                        <input type="text" class="form-control" name="name" id="editName" required>
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">IP адрес</label>
                        <input type="text" class="form-control" name="ip" id="editIp" required>
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Порт</label>
                        <input type="number" class="form-control" name="port" id="editPort">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label">Новый SDK пароль (оставьте пустым чтобы не менять)</label>
                        <input type="password" class="form-control" name="sdk_password" id="editPassword" 
                               placeholder="Оставьте пустым если не нужно менять">
                    </div>
                    
                    <div class="form-check mb-3">
                        <input type="checkbox" class="form-check-input" name="ssl" id="editSsl">
                        <label class="form-check-label">Использовать SSL</label>
                    </div>
                    
                    <button type="submit" class="btn btn-warning w-100">
                        <i class="bi bi-check-lg"></i> Сохранить изменения
                    </button>
                </form>
            </div>
        </div>
    </div>
</div>
{% endif %}

{% endblock %}

{% block scripts %}
<script>
// ============================================
// ОБРАБОТЧИК WEBSOCKET ОБНОВЛЕНИЙ
// ============================================
window.handleUpdate = function(data) {
    var totalCameras = 0;
    var onlineCameras = 0;
    var totalAlerts = 0;
    
    data.servers.forEach(function(server) {
        totalCameras += server.ch_t || 0;
        onlineCameras += server.ch_o || 0;
        totalAlerts += server.alerts || 0;
        
        // Находим строку сервера по data-server-id
        var row = document.querySelector('[data-server-id="' + server.id + '"]');
        if (!row) return;
        
        // Обновляем статус (точку)
        var dot = row.querySelector('.status-dot');
        if (dot) {
            if (!server.ok) {
                dot.className = 'status-dot offline';
            } else if (server.ch_o === server.ch_t) {
                dot.className = 'status-dot online';
            } else if (server.ch_o > 0) {
                dot.className = 'status-dot warning';
            } else {
                dot.className = 'status-dot offline';
            }
        }
        
        // Обновляем значения метрик
        var values = row.querySelectorAll('.metric-value');
        if (server.ok && values.length >= 6) {
            // Камеры
            values[0].textContent = server.ch_o + '/' + server.ch_t;
            // CPU
            values[1].textContent = server.cpu.toFixed(1) + '%';
            // Диски
            values[2].textContent = server.disks ? '✅' : '❌';
            // Архив
            values[3].textContent = server.arch.toFixed(1) + ' дн';
            // Uptime
            var days = Math.floor(server.uptime_d || 0);
            var hours = Math.floor((server.uptime_s || 0) % 86400 / 3600);
            values[4].textContent = days + 'д ' + hours + 'ч';
            // Отклик
            values[5].textContent = (server.rt || 0) + 'мс';
        }
        
        // Обновляем бейдж алертов
        var badge = row.querySelector('.alerts-badge');
        if (badge) {
            if (server.alerts > 0) {
                badge.textContent = server.alerts;
                badge.className = 'badge bg-danger fs-6 alerts-badge';
                badge.style.opacity = '1';
            } else {
                badge.textContent = '0';
                badge.className = 'badge bg-success alerts-badge';
                badge.style.opacity = '0.3';
            }
        }
    });
    
    // Обновляем карточки статистики
    document.getElementById('statServers').textContent = data.servers.length;
    document.getElementById('statOnline').textContent = onlineCameras;
    document.getElementById('statOffline').textContent = totalCameras - onlineCameras;
    document.getElementById('statAlerts').textContent = totalAlerts;
    
    var alertsCard = document.getElementById('statAlertsCard');
    alertsCard.className = 'stat-card ' + (totalAlerts > 0 ? 'danger' : 'success');
};

// ============================================
// КНОПКИ РЕДАКТИРОВАНИЯ
// ============================================
document.querySelectorAll('.edit-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
        // Заполняем форму данными из data-атрибутов
        document.getElementById('editId').value = this.dataset.id;
        document.getElementById('editName').value = this.dataset.name;
        document.getElementById('editIp').value = this.dataset.ip;
        document.getElementById('editPort').value = this.dataset.port;
        document.getElementById('editSsl').checked = (
            this.dataset.ssl === '1' || this.dataset.ssl === 'True'
        );
        document.getElementById('editPassword').value = '';
        
        // Показываем модальное окно
        new bootstrap.Modal(document.getElementById('editModal')).show();
    });
});

// ============================================
// СОХРАНЕНИЕ ИЗМЕНЕНИЙ
// ============================================
document.getElementById('editForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    var formData = new FormData(this);
    var data = Object.fromEntries(formData);
    data.port = parseInt(data.port);
    data.ssl = data.ssl === 'on';
    data.id = parseInt(data.id);
    
    var response = await fetch('/api/servers', {
        method: 'PUT',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    
    if (response.ok) {
        location.reload();
    } else {
        alert('Ошибка при сохранении изменений');
    }
});

// ============================================
// УДАЛЕНИЕ СЕРВЕРА
// ============================================
async function deleteServer(id) {
    if (!confirm('Вы уверены что хотите удалить сервер #' + id + '? Все данные будут удалены.')) {
        return;
    }
    
    var response = await fetch('/api/servers?id=' + id, { method: 'DELETE' });
    
    if (response.ok) {
        location.reload();
    } else {
        alert('Ошибка при удалении сервера');
    }
}

// ============================================
// ДОБАВЛЕНИЕ СЕРВЕРА
// ============================================
document.getElementById('addForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    var formData = new FormData(this);
    var data = Object.fromEntries(formData);
    data.port = parseInt(data.port);
    data.ssl = data.ssl === 'on';
    
    var response = await fetch('/api/servers', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    
    if (response.ok) {
        location.reload();
    } else {
        alert('Ошибка при добавлении сервера');
    }
});

// ============================================
// ТЕСТ ПОДКЛЮЧЕНИЯ
// ============================================
async function testConnection() {
    var form = document.getElementById('addForm');
    var formData = new FormData(form);
    var data = Object.fromEntries(formData);
    data.port = parseInt(data.port);
    data.ssl = data.ssl === 'on';
    
    var resultDiv = document.getElementById('testResult');
    resultDiv.style.display = 'block';
    resultDiv.innerHTML = '<div class="alert alert-info">Проверка подключения...</div>';
    
    try {
        var response = await fetch('/test-connection', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(data)
        });
        
        var result = await response.json();
        
        if (result.success) {
            resultDiv.innerHTML = 
                '<div class="alert alert-success">' +
                '<strong>✅ Подключение успешно!</strong><br>' +
                'Время ответа: ' + result.response_time_ms + 'мс<br>' +
                'Камер: ' + (result.data?.channels_online || 0) + '/' + (result.data?.channels_total || 0) + '<br>' +
                'CPU: ' + (result.data?.cpu?.toFixed(1) || 'N/A') + '%<br>' +
                'Архив: ' + (result.data?.archive_days?.toFixed(1) || 'N/A') + ' дн' +
                '</div>';
        } else {
            resultDiv.innerHTML = 
                '<div class="alert alert-danger">' +
                '<strong>❌ Ошибка подключения</strong><br>' +
                escapeHtml(result.error || 'Неизвестная ошибка') +
                '</div>';
        }
    } catch (err) {
        resultDiv.innerHTML = '<div class="alert alert-danger">Ошибка: ' + escapeHtml(err.message) + '</div>';
    }
}
</script>
{% endblock %}

{% block footer %}
<div class="text-center mt-4 mb-3" style="font-size:0.75rem; color:var(--muted);">
    TRASSIR Monitor {{ build_info.version }} · обновлено: {{ build_info.mtime }}{% if build_info.commit != '?' %} · коммит: {{ build_info.commit }}{% endif %}
</div>
{% endblock %}
DASHEOF
echo "    ✓ dashboard.html создан ($(wc -c < $INSTALL_DIR/templates/dashboard.html) байт)"

# ---------- server.html ----------
echo "  • Создание server.html..."
cat > $INSTALL_DIR/templates/server.html << 'SERVEREOF'
{% extends "base.html" %}

{% block title %}{{ server.name }} — TRASSIR Monitor{% endblock %}

{% block content %}

<!-- Навигация -->
<nav class="mb-4">
    <a href="/" class="btn btn-outline-light btn-sm">
        <i class="bi bi-arrow-left"></i> Назад к списку серверов
    </a>
</nav>

<!-- Заголовок -->
<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h2 class="mb-1">{{ server.name }}</h2>
        <p class="mb-0" style="color: var(--muted);">
            <i class="bi bi-hdd-stack"></i> {{ server.ip }}:{{ server.port }}
        </p>
    </div>
    <span class="badge bg-{% if cur and cur.ch_online == cur.ch_total %}success{% else %}warning{% endif %} fs-6">
        {% if cur %}
            {{ cur.ch_online }}/{{ cur.ch_total }} камер онлайн
        {% else %}
            Нет данных
        {% endif %}
    </span>
</div>

<!-- Метрики -->
<div class="row g-3 mb-4">
    <div class="col-md-2">
        <div class="card">
            <div class="card-body text-center">
                <i class="bi bi-cpu" style="font-size: 2rem; color: var(--acc);"></i>
                <h3 class="mt-2 mb-0" id="cpuValue">
                    {{ "%.1f"|format(cur.cpu) if cur else '--' }}%
                </h3>
                <small style="color: var(--muted);">Загрузка CPU</small>
            </div>
        </div>
    </div>
    <div class="col-md-2">
        <div class="card">
            <div class="card-body text-center">
                <i class="bi bi-camera-video" style="font-size: 2rem; color: var(--green);"></i>
                <h3 class="mt-2 mb-0" id="camerasValue">
                    {{ cur.ch_online if cur else '--' }}/{{ cur.ch_total if cur else '--' }}
                </h3>
                <small style="color: var(--muted);">Камеры онлайн</small>
            </div>
        </div>
    </div>
    <div class="col-md-2">
        <div class="card">
            <div class="card-body text-center">
                <i class="bi bi-hdd" style="font-size: 2rem; color: {% if cur and cur.disks == 1 %}var(--green){% else %}var(--red){% endif %};"></i>
                <h3 class="mt-2 mb-0" id="disksValue">
                    {% if cur %}
                        {% if cur.disks == 1 %}✅{% else %}❌{% endif %}
                    {% else %}--{% endif %}
                </h3>
                <small style="color: var(--muted);">Состояние дисков</small>
            </div>
        </div>
    </div>
    <div class="col-md-2">
        <div class="card">
            <div class="card-body text-center">
                <i class="bi bi-archive" style="font-size: 2rem; color: var(--yellow);"></i>
                <h3 class="mt-2 mb-0" id="archiveValue">
                    {{ "%.1f"|format(cur.arch) if cur else '--' }} дн
                </h3>
                <small style="color: var(--muted);">Глубина архива</small>
            </div>
        </div>
    </div>
    <div class="col-md-2">
        <div class="card">
            <div class="card-body text-center">
                <i class="bi bi-clock" style="font-size: 2rem; color: #8b5cf6;"></i>
                <h3 class="mt-2 mb-0" id="uptimeValue">
                    {% if cur and cur.uptime %}
                        {{ (cur.uptime // 86400)|int }}д
                    {% else %}--{% endif %}
                </h3>
                <small style="color: var(--muted);">Uptime</small>
            </div>
        </div>
    </div>
    <div class="col-md-2">
        <div class="card">
            <div class="card-body text-center">
                <i class="bi bi-speedometer2" style="font-size: 2rem; color: #ec4899;"></i>
                <h3 class="mt-2 mb-0">{{ cur.rt if cur else '--' }}мс</h3>
                <small style="color: var(--muted);">Время отклика</small>
            </div>
        </div>
    </div>
</div>

<!-- График и алерты -->
<div class="row g-3">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <span><i class="bi bi-graph-up"></i> История за 24 часа</span>
                <div class="btn-group btn-group-sm">
                    <button class="btn btn-outline-light active" onclick="loadHistory(0.5, this)">30м</button>
                    <button class="btn btn-outline-light" onclick="loadHistory(6, this)">6ч</button>
                    <button class="btn btn-outline-light" onclick="loadHistory(24, this)">24ч</button>
                    <button class="btn btn-outline-light" onclick="loadHistory(168, this)">7д</button>
                </div>
            </div>
            <div class="card-body">
                <div class="chart-container">
                    <canvas id="historyChart"></canvas>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-4">
        <div class="card h-100">
            <div class="card-header">
                <span><i class="bi bi-bell"></i> Алерты</span>
                {% if logged_in %}
                <button class="btn btn-sm btn-outline-success" onclick="acknowledgeAlerts()">
                    <i class="bi bi-check-all"></i> Сбросить все
                </button>
                {% endif %}
            </div>
            <div class="card-body" style="max-height: 500px; overflow-y: auto;">
                {% if alerts_active %}
                    <div class="mb-2" style="font-size:0.75rem; color:var(--muted); text-transform:uppercase; letter-spacing:1px;">Активные проблемы</div>
                    {% for alert in alerts_active %}
                    <div class="alert-item {{ alert.level }}">
                        <div class="d-flex justify-content-between align-items-start mb-2">
                            <strong>
                                {% if alert.level == 'critical' %}🔴 КРИТИЧЕСКАЯ
                                {% elif alert.level == 'warning' %}⚠️ ПРЕДУПРЕЖДЕНИЕ
                                {% else %}ℹ️ ИНФОРМАЦИЯ{% endif %}
                            </strong>
                            <span class="badge bg-dark">{{ alert.ts }}</span>
                        </div>
                        <div class="d-flex justify-content-between align-items-end gap-2">
                            <div>{{ alert.msg }}</div>
                            {% if logged_in %}
                            <button class="btn btn-sm btn-outline-secondary flex-shrink-0" onclick="dismissAlert({{ alert.id }})" title="Сбросить только этот алерт">
                                <i class="bi bi-x-lg"></i>
                            </button>
                            {% endif %}
                        </div>
                    </div>
                    {% endfor %}
                {% else %}
                    <div class="text-center py-4">
                        <i class="bi bi-check-circle" style="font-size: 3rem; color: var(--green);"></i>
                        <p class="mt-2" style="color: var(--muted);">Нет активных проблем</p>
                    </div>
                {% endif %}
                {% if alerts_history %}
                    <div class="mt-3 mb-2" style="font-size:0.75rem; color:var(--muted); text-transform:uppercase; letter-spacing:1px;">
                        История (последние {{ alerts_history|length }})
                    </div>
                    {% for alert in alerts_history %}
                    <div class="alert-item {{ alert.level }}" style="opacity:0.4;">
                        <div class="d-flex justify-content-between align-items-start mb-1">
                            <strong style="font-size:0.85rem;">
                                {% if alert.level == 'critical' %}🔴{% elif alert.level == 'warning' %}⚠️{% else %}ℹ️{% endif %}
                                {{ alert.msg }}
                            </strong>
                            <span class="badge bg-dark" style="font-size:0.7rem; white-space:nowrap;">{{ alert.ts }}</span>
                        </div>
                    </div>
                    {% endfor %}
                {% endif %}
            </div>
        </div>
    </div>
</div>

{% endblock %}

{% block scripts %}
<script>
// ============================================
// ГРАФИК
// ============================================
var historyChart = null;

function loadHistory(hours, btn) {
    // Обновляем активную кнопку
    if (btn) {
        document.querySelectorAll('.btn-group .btn').forEach(function(b) {
            b.classList.remove('active');
        });
        btn.classList.add('active');
    }

    fetch('/api/hist/{{ server.id }}?h=' + hours)
        .then(function(response) { return response.json(); })
        .then(function(data) {
            if (!data.length) return;

            // Агрегация — максимум 60 точек на графике
            var maxPoints = 60;
            var aggregated = data;
            if (data.length > maxPoints) {
                var step = Math.ceil(data.length / maxPoints);
                aggregated = [];
                for (var i = 0; i < data.length; i += step) {
                    var chunk = data.slice(i, i + step);
                    var avg = function(key) {
                        return chunk.reduce(function(s, r) { return s + (r[key] || 0); }, 0) / chunk.length;
                    };
                    aggregated.push({
                        ts:        chunk[Math.floor(chunk.length / 2)].ts,
                        cpu:       avg('cpu'),
                        ch_online: Math.round(avg('ch_online')),
                        ch_total:  Math.round(avg('ch_total')),
                        arch:      avg('arch')
                    });
                }
            }

            // Формат меток времени зависит от диапазона
            var labels = aggregated.map(function(item) {
                var d = new Date(item.ts);
                if (hours <= 1) {
                    return d.toLocaleTimeString('ru-RU', {hour: '2-digit', minute: '2-digit', second: '2-digit'});
                } else if (hours <= 24) {
                    return d.toLocaleTimeString('ru-RU', {hour: '2-digit', minute: '2-digit'});
                } else {
                    return d.toLocaleDateString('ru-RU', {day: '2-digit', month: '2-digit'}) + ' ' +
                           d.toLocaleTimeString('ru-RU', {hour: '2-digit', minute: '2-digit'});
                }
            });

            var ctx = document.getElementById('historyChart').getContext('2d');
            if (historyChart) { historyChart.destroy(); }

            historyChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [
                        {
                            label: 'CPU %',
                            data: aggregated.map(function(item) { return item.cpu; }),
                            borderColor: '#667eea',
                            backgroundColor: 'rgba(102, 126, 234, 0.1)',
                            fill: true, tension: 0.4, borderWidth: 2
                        },
                        {
                            label: 'Камеры онлайн',
                            data: aggregated.map(function(item) { return item.ch_online; }),
                            borderColor: '#10b981',
                            backgroundColor: 'rgba(16, 185, 129, 0.1)',
                            fill: true, tension: 0.4, borderWidth: 2, yAxisID: 'y1'
                        },
                        {
                            label: 'Архив (дни)',
                            data: aggregated.map(function(item) { return item.arch; }),
                            borderColor: '#f59e0b',
                            backgroundColor: 'rgba(245, 158, 11, 0.1)',
                            fill: true, tension: 0.4, borderWidth: 2, yAxisID: 'y2'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { mode: 'index', intersect: false },
                    plugins: {
                        legend: { labels: { color: '#d1d5db' } }
                    },
                    scales: {
                        y: {
                            type: 'linear', display: true, position: 'left',
                            title: { display: true, text: 'CPU %', color: '#667eea' },
                            grid: { color: 'rgba(255,255,255,0.05)' },
                            ticks: { color: '#6b7280' }
                        },
                        y1: {
                            type: 'linear', display: true, position: 'right',
                            title: { display: true, text: 'Камеры', color: '#10b981' },
                            grid: { drawOnChartArea: false },
                            ticks: { color: '#6b7280' }
                        },
                        y2: {
                            type: 'linear', display: false, position: 'right',
                            grid: { drawOnChartArea: false }
                        },
                        x: {
                            ticks: {
                                color: '#6b7280',
                                maxTicksLimit: 10,
                                maxRotation: 0
                            },
                            grid: { color: 'rgba(255,255,255,0.05)' }
                        }
                    }
                }
            });
        });
}

// ============================================
// ОБНОВЛЕНИЕ МЕТРИК
// ============================================
function refreshMetrics() {
    fetch('/api/health/{{ server.id }}')
        .then(function(response) { return response.json(); })
        .then(function(data) {
            if (data.ok) {
                document.getElementById('cpuValue').textContent = data.cpu.toFixed(1) + '%';
                document.getElementById('camerasValue').textContent = data.ch_o + '/' + data.ch_t;
                document.getElementById('archiveValue').textContent = data.arch.toFixed(1) + ' дн';
                document.getElementById('uptimeValue').textContent = Math.floor(data.uptime / 86400) + 'д';
            }
        });
}

// ============================================
// СБРОС АЛЕРТОВ
// ============================================
function acknowledgeAlerts() {
    fetch('/api/ack/{{ server.id }}', { method: 'POST' })
        .then(function() {
            location.reload();
        });
}

function dismissAlert(alertId) {
    fetch('/api/alerts/' + alertId + '/dismiss', { method: 'POST' })
        .then(function() {
            location.reload();
        });
}

// Запуск
loadHistory(0.5);
refreshMetrics();
setInterval(refreshMetrics, 30000);
</script>
{% endblock %}
SERVEREOF
echo "    ✓ server.html создан ($(wc -c < $INSTALL_DIR/templates/server.html) байт)"

# ---------- settings.html ----------
echo "  • Создание settings.html..."
cat > $INSTALL_DIR/templates/settings.html << 'SETTINGSEOF'
{% extends "base.html" %}

{% block title %}Настройки — TRASSIR Monitor{% endblock %}

{% block content %}

<style>
    #settingsForm .form-control {
        background: #0a0d14 !important;
        border: 1px solid #252b36 !important;
        color: #d1d5db !important;
    }
    #settingsForm .form-control:focus {
        background: #0a0d14 !important;
        border-color: #667eea !important;
        color: #ffffff !important;
        box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.2) !important;
    }
    #settingsForm .form-control::placeholder { color: #6b7280 !important; }
    #settingsForm .text-muted { color: #6b7280 !important; }
</style>

<nav class="mb-4">
    <a href="/" class="btn btn-outline-light btn-sm">
        <i class="bi bi-arrow-left"></i> Назад на дашборд
    </a>
</nav>

<h2 class="mb-4"><i class="bi bi-gear"></i> Настройки системы</h2>

{% if not logged_in %}
<div class="card mb-4">
    <div class="card-body text-center py-4">
        <i class="bi bi-lock" style="font-size: 3rem; color: var(--muted);"></i>
        <h5 class="mt-3" style="color: var(--muted);">Для изменения настроек необходимо войти</h5>
        <a href="/login" class="btn btn-primary mt-2">
            <i class="bi bi-box-arrow-in-right"></i> Войти
        </a>
    </div>
</div>
{% endif %}

<div class="row g-4">
    <!-- Параметры мониторинга -->
    {% if logged_in %}
    <div class="col-lg-6">
        <div class="card">
            <div class="card-header">
                <i class="bi bi-sliders"></i> Параметры мониторинга
            </div>
            <div class="card-body">
                <form id="settingsForm">
                    <div class="mb-3">
                        <label class="form-label">Интервал опроса (секунд)</label>
                        <input type="number" class="form-control" name="poll_interval"
                               value="{{ settings.poll_interval }}">
                        <small class="text-muted">Как часто опрашивать серверы TRASSIR</small>
                    </div>
                    <div class="mb-3">
                        <label class="form-label">Хранение данных (дней)</label>
                        <input type="number" class="form-control" name="retention_days"
                               value="{{ settings.retention_days }}">
                    </div>
                    <div class="row">
                        <div class="col-6">
                            <label class="form-label">CPU Warning (%)</label>
                            <input type="number" class="form-control" name="cpu_warning"
                                   value="{{ settings.cpu_warning }}">
                        </div>
                        <div class="col-6">
                            <label class="form-label">CPU Critical (%)</label>
                            <input type="number" class="form-control" name="cpu_critical"
                                   value="{{ settings.cpu_critical }}">
                        </div>
                    </div>
                    <div class="row mt-3">
                        <div class="col-6">
                            <label class="form-label">Архив Warning (дней)</label>
                            <input type="number" class="form-control" name="archive_warning_days"
                                   value="{{ settings.archive_warning_days }}">
                        </div>
                        <div class="col-6">
                            <label class="form-label">Архив Critical (дней)</label>
                            <input type="number" class="form-control" name="archive_critical_days"
                                   value="{{ settings.archive_critical_days }}">
                        </div>
                    </div>
                    <button type="submit" class="btn btn-primary mt-3">
                        <i class="bi bi-check-lg"></i> Сохранить настройки
                    </button>
                </form>
            </div>
        </div>

        <!-- Смена пароля -->
        <div class="card mt-4">
            <div class="card-header">
                <i class="bi bi-key"></i> Смена пароля администратора
            </div>
            <div class="card-body">
                <form id="passwordForm">
                    <div class="mb-3">
                        <label class="form-label">Новый пароль</label>
                        <input type="password" class="form-control" id="newPassword"
                               placeholder="Введите новый пароль">
                    </div>
                    <div class="mb-3">
                        <label class="form-label">Подтверждение</label>
                        <input type="password" class="form-control" id="confirmPassword"
                               placeholder="Повторите пароль">
                    </div>
                    <button type="submit" class="btn btn-warning">
                        <i class="bi bi-key"></i> Сменить пароль
                    </button>
                </form>
            </div>
        </div>
    </div>
    {% endif %}

    <!-- Список серверов -->
    <div class="col-lg-6">
        <div class="card">
            <div class="card-header">
                <span><i class="bi bi-hdd-stack"></i> Список серверов</span>
                {% if logged_in %}
                <button class="btn btn-sm btn-primary" data-bs-toggle="modal" data-bs-target="#addModal">
                    <i class="bi bi-plus-lg"></i> Добавить
                </button>
                {% endif %}
            </div>
            <div class="card-body">
                {% if servers %}
                <table class="table table-dark table-hover">
                    <thead>
                        <tr>
                            <th>Название</th>
                            <th>IP адрес</th>
                            <th>Порт</th>
                            {% if logged_in %}<th>Действия</th>{% endif %}
                        </tr>
                    </thead>
                    <tbody>
                        {% for server in servers %}
                        <tr>
                            <td>{{ server.name }}</td>
                            <td>{{ server.ip }}</td>
                            <td>{{ server.port }}</td>
                            {% if logged_in %}
                            <td>
                                <button class="btn btn-sm btn-outline-warning edit-btn"
                                        data-id="{{ server.id }}"
                                        data-name="{{ server.name }}"
                                        data-ip="{{ server.ip }}"
                                        data-port="{{ server.port }}"
                                        data-ssl="{{ server.ssl }}">
                                    <i class="bi bi-pencil"></i>
                                </button>
                                <button class="btn btn-sm btn-danger"
                                        onclick="if(confirm('Удалить {{ server.name }}?'))fetch('/api/servers?id={{ server.id }}',{method:'DELETE'}).then(function(){location.reload()})">
                                    <i class="bi bi-trash"></i>
                                </button>
                            </td>
                            {% endif %}
                        </tr>
                        {% endfor %}
                    </tbody>
                </table>
                {% else %}
                <p class="text-muted text-center py-3">Нет добавленных серверов</p>
                {% endif %}
            </div>
        </div>

        {% if logged_in %}
        <!-- Экспорт / импорт регистраторов -->
        <div class="card mt-4">
            <div class="card-header">
                <i class="bi bi-arrow-down-up"></i> Экспорт / импорт регистраторов
            </div>
            <div class="card-body">
                <p style="font-size:0.85rem; color:var(--muted);">
                    Экспорт сохраняет названия, адреса и SDK-пароли всех серверов
                    в один файл — для бэкапа или переноса на другую установку.
                    <strong style="color:var(--yellow);">Файл содержит пароли в открытом виде</strong> —
                    храните и передавайте его так же осторожно, как сами пароли.
                </p>
                <a href="/api/servers/export" class="btn btn-outline-primary btn-sm mb-3" download>
                    <i class="bi bi-download"></i> Экспортировать в файл
                </a>
                <hr style="border-color: var(--border);">
                <p style="font-size:0.85rem; color:var(--muted);" class="mb-2">
                    Импорт добавляет серверы, которых ещё нет (по названию), и
                    обновляет уже существующие. Пустой пароль в файле не затирает
                    уже сохранённый.
                </p>
                <input type="file" class="form-control form-control-sm mb-2" id="importFile" accept=".json,application/json">
                <button class="btn btn-outline-success btn-sm" onclick="importServers()">
                    <i class="bi bi-upload"></i> Импортировать из файла
                </button>
                <div id="importResult" class="mt-2"></div>
            </div>
        </div>
        {% endif %}
    </div>
</div>

{% if logged_in %}
<!-- Модальное окно добавления сервера -->
<div class="modal fade" id="addModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title"><i class="bi bi-plus-circle"></i> Добавить сервер</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <form id="addForm">
                    <div class="mb-3">
                        <label class="form-label">Название *</label>
                        <input type="text" class="form-control" name="name" required placeholder="Главный офис">
                    </div>
                    <div class="mb-3">
                        <label class="form-label">IP адрес *</label>
                        <input type="text" class="form-control" name="ip" required placeholder="192.168.1.100">
                    </div>
                    <div class="mb-3">
                        <label class="form-label">Порт</label>
                        <input type="number" class="form-control" name="port" value="8080">
                    </div>
                    <div class="mb-3">
                        <label class="form-label">SDK Пароль</label>
                        <input type="password" class="form-control" name="sdk_password"
                               placeholder="Настройки TRASSIR → Веб-сервер → Пароль SDK">
                    </div>
                    <div class="form-check mb-3">
                        <input type="checkbox" class="form-check-input" name="ssl" checked>
                        <label class="form-check-label">Использовать SSL</label>
                    </div>
                    <div class="d-flex gap-2">
                        <button type="button" class="btn btn-outline-info" onclick="testConnection()">
                            <i class="bi bi-lightning"></i> Проверить
                        </button>
                        <button type="submit" class="btn btn-primary flex-grow-1">
                            <i class="bi bi-plus-lg"></i> Добавить
                        </button>
                    </div>
                    <div id="testResult" class="mt-3" style="display:none;"></div>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- Модальное окно редактирования -->
<div class="modal fade" id="editModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title"><i class="bi bi-pencil"></i> Изменить сервер</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <form id="editForm">
                    <input type="hidden" name="id" id="editId">
                    <div class="mb-3">
                        <label class="form-label">Название</label>
                        <input type="text" class="form-control" name="name" id="editName" required>
                    </div>
                    <div class="mb-3">
                        <label class="form-label">IP адрес</label>
                        <input type="text" class="form-control" name="ip" id="editIp" required>
                    </div>
                    <div class="mb-3">
                        <label class="form-label">Порт</label>
                        <input type="number" class="form-control" name="port" id="editPort">
                    </div>
                    <div class="mb-3">
                        <label class="form-label">Новый SDK пароль (пусто = не менять)</label>
                        <input type="password" class="form-control" name="sdk_password" id="editPassword">
                    </div>
                    <div class="form-check mb-3">
                        <input type="checkbox" class="form-check-input" name="ssl" id="editSsl">
                        <label class="form-check-label">Использовать SSL</label>
                    </div>
                    <button type="submit" class="btn btn-warning w-100">
                        <i class="bi bi-check-lg"></i> Сохранить
                    </button>
                </form>
            </div>
        </div>
    </div>
</div>
{% endif %}

<!-- Telegram и Mail секции -->
<div class="row g-4 mt-0">
<!-- Telegram секция — показывается если служба установлена -->
<div class="col-lg-6" id="telegramSection" style="display:none;">
    <div class="card">
        <div class="card-header">
            <span><i class="bi bi-telegram"></i> Telegram уведомления</span>
        </div>
        <div class="card-body" id="telegramBody">
            {% if not logged_in %}
            <div class="text-center py-3">
                <i class="bi bi-lock" style="color:var(--muted);font-size:2rem;"></i>
                <p class="mt-2" style="color:var(--muted);">Войдите для управления Telegram</p>
                <a href="/login" class="btn btn-primary btn-sm">Войти</a>
            </div>
            {% else %}
            <p style="color:var(--muted);">Загрузка...</p>
            {% endif %}
        </div>
    </div>
</div>

<!-- Mail секция — показывается если служба установлена -->
<div class="col-lg-6" id="mailSection" style="display:none;">
    <div class="card">
        <div class="card-header">
            <span><i class="bi bi-envelope"></i> Email уведомления</span>
        </div>
        <div class="card-body" id="mailBody">
            {% if not logged_in %}
            <div class="text-center py-3">
                <i class="bi bi-lock" style="color:var(--muted);font-size:2rem;"></i>
                <p class="mt-2" style="color:var(--muted);">Войдите для управления Email</p>
                <a href="/login" class="btn btn-primary btn-sm">Войти</a>
            </div>
            {% else %}
            <p style="color:var(--muted);">Загрузка...</p>
            {% endif %}
        </div>
    </div>
</div>
</div>

{% endblock %}

{% block scripts %}
<script>
{% if logged_in %}
// Сохранение настроек мониторинга
document.getElementById('settingsForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    var data = Object.fromEntries(new FormData(this));
    var r = await fetch('/api/settings', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    alert(r.ok ? 'Настройки сохранены!' : 'Ошибка при сохранении');
});

// Смена пароля
document.getElementById('passwordForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    var p1 = document.getElementById('newPassword').value;
    var p2 = document.getElementById('confirmPassword').value;
    if (!p1) { alert('Введите пароль'); return; }
    if (p1 !== p2) { alert('Пароли не совпадают'); return; }
    var r = await fetch('/api/settings', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({admin_password: p1})
    });
    if (r.ok) {
        alert('Пароль изменён!');
        document.getElementById('newPassword').value = '';
        document.getElementById('confirmPassword').value = '';
    }
});

// Добавление сервера
document.getElementById('addForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    var data = Object.fromEntries(new FormData(this));
    data.port = parseInt(data.port);
    data.ssl = data.ssl === 'on';
    var r = await fetch('/api/servers', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    if (r.ok) location.reload();
    else alert('Ошибка при добавлении');
});

// Редактирование
document.querySelectorAll('.edit-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
        document.getElementById('editId').value = this.dataset.id;
        document.getElementById('editName').value = this.dataset.name;
        document.getElementById('editIp').value = this.dataset.ip;
        document.getElementById('editPort').value = this.dataset.port;
        document.getElementById('editSsl').checked = (this.dataset.ssl === '1' || this.dataset.ssl === 'True');
        document.getElementById('editPassword').value = '';
        new bootstrap.Modal(document.getElementById('editModal')).show();
    });
});

document.getElementById('editForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    var data = Object.fromEntries(new FormData(this));
    data.port = parseInt(data.port);
    data.ssl = data.ssl === 'on';
    data.id = parseInt(data.id);
    var r = await fetch('/api/servers', {
        method: 'PUT',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    if (r.ok) location.reload();
    else alert('Ошибка при сохранении');
});

async function importServers() {
    var fileInput = document.getElementById('importFile');
    var resultDiv = document.getElementById('importResult');
    if (!fileInput.files.length) {
        alert('Сначала выберите файл');
        return;
    }
    var text = await fileInput.files[0].text();
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        resultDiv.innerHTML = '<div class="alert alert-danger py-2 mb-0">Файл повреждён или это не JSON</div>';
        return;
    }
    var r = await fetch('/api/servers/import', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    var result = await r.json();
    if (r.ok) {
        var msg = 'Добавлено: ' + result.added + ', обновлено: ' + result.updated;
        if (result.errors && result.errors.length) {
            msg += '<br><span style="color:var(--yellow);">' + result.errors.map(escapeHtml).join('<br>') + '</span>';
        }
        resultDiv.innerHTML = '<div class="alert alert-success py-2 mb-0">' + msg + '</div>';
        setTimeout(function() { location.reload(); }, 1800);
    } else {
        resultDiv.innerHTML = '<div class="alert alert-danger py-2 mb-0">' + escapeHtml(result.error || 'Ошибка импорта') + '</div>';
    }
}

async function testConnection() {
    var data = Object.fromEntries(new FormData(document.getElementById('addForm')));
    data.port = parseInt(data.port);
    data.ssl = data.ssl === 'on';
    var resultDiv = document.getElementById('testResult');
    resultDiv.style.display = 'block';
    resultDiv.innerHTML = '<div class="alert alert-info">Проверка...</div>';
    try {
        var r = await fetch('/test-connection', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(data)
        });
        var result = await r.json();
        if (result.success) {
            resultDiv.innerHTML = '<div class="alert alert-success">✅ Подключение успешно! Камер: ' +
                (result.data?.channels_online||0) + '/' + (result.data?.channels_total||0) + '</div>';
        } else {
            resultDiv.innerHTML = '<div class="alert alert-danger">❌ ' + escapeHtml(result.error||'Ошибка') + '</div>';
        }
    } catch(e) {
        resultDiv.innerHTML = '<div class="alert alert-danger">Ошибка: ' + e.message + '</div>';
    }
}
{% endif %}

// ============================================
// TELEGRAM И MAIL — загружаем если установлены
// ============================================
var servicesLoaded = false;

async function loadServices() {
    if (servicesLoaded) return;
    servicesLoaded = true;
    try {
        var r = await fetch('/api/services/status');
        var s = await r.json();
        if (s.telegram) {
            document.getElementById('telegramSection').style.display = 'block';
            {% if logged_in %}loadTelegramSection();{% endif %}
        }
        if (s.mail) {
            document.getElementById('mailSection').style.display = 'block';
            {% if logged_in %}loadMailSection();{% endif %}
        }
    } catch(e) {}
}

async function loadTelegramSection() {
    var sec = document.getElementById('telegramSection');
    if (!sec) return;
    sec.style.display = 'block';
    {% if logged_in %}
    try {
        var r = await fetch('/api/telegram/chats');
        var chats = await r.json();
        var rs = await fetch('/api/telegram/settings');
        var cfg = await rs.json();
        renderTelegram(chats, cfg);
    } catch(e) { console.error(e); }
    {% endif %}
}

function renderTelegram(chats, cfg) {
    var html = '';
    if (cfg.token_configured) {
        html += '<div class="alert alert-success py-2 mb-3">✅ Токен: ' + escapeHtml(cfg.token_masked||'настроен') + '</div>';
    } else {
        html += '<div class="alert alert-warning py-2 mb-3">⚠️ Токен не настроен</div>';
    }
    html += renderTgTransport(cfg);
    html += '<div class="mb-3"><strong>Получатели:</strong></div>';
    if (chats.length) {
        chats.forEach(function(c) {
            var enabled = c.enabled == 1;
            html += '<div class="d-flex justify-content-between align-items-center mb-2 p-2" style="background:var(--bg);border-radius:8px;opacity:' + (enabled?'1':'0.5') + '">' +
                '<span>' + (c.name ? escapeHtml(c.name) : '<span style="color:var(--muted)">без имени</span>') +
                ' <small style="color:var(--muted);">(' + escapeHtml(c.chat_id) + ')</small></span>' +
                '<div class="d-flex gap-1">' +
                '<button class="btn btn-sm ' + (enabled ? 'btn-success' : 'btn-outline-secondary') + '" onclick="toggleTgChat(' + c.id + ',' + (enabled?0:1) + ')" title="' + (enabled?'Выключить':'Включить') + '">' +
                '<i class="bi bi-' + (enabled?'bell':'bell-slash') + '"></i></button>' +
                '<button class="btn btn-sm btn-outline-danger" onclick="deleteTgChat(' + c.id + ')"><i class="bi bi-trash"></i></button>' +
                '</div></div>';
        });
    } else {
        html += '<p style="color:var(--muted);">Нет получателей</p>';
    }
    html += '<div class="d-flex gap-2 mt-3">' +
        '<input type="text" id="newChatId" class="form-control" placeholder="Chat ID">' +
        '<input type="text" id="newChatName" class="form-control" placeholder="Имя">' +
        '<button class="btn btn-primary" onclick="addTgChat()"><i class="bi bi-plus"></i></button>' +
        '</div>' +
        '<button class="btn btn-outline-info btn-sm mt-2" onclick="testTelegram()"><i class="bi bi-send"></i> Тест</button>' +
        '<div id="tgTestResult" class="mt-2"></div>';
    document.getElementById('telegramBody').innerHTML = html;
}

function renderTgTransport(cfg) {
    var proxyConfigured = !!(cfg.proxy_url_configured || cfg.proxy_configured);
    var proxyMasked = cfg.proxy_url_masked || cfg.proxy_masked || '';
    var apiBase = cfg.api_base || '';
    var mode = apiBase ? 'relay' : (proxyConfigured ? 'proxy' : 'direct');
    var apiKeyHint = cfg.api_key_configured ? ('настроен: ' + escapeHtml(cfg.api_key_masked || '***')) : 'не настроен';
    window.__tgProxyConfigured = proxyConfigured;

    var html = '<div class="mb-3 p-2" style="background:var(--bg);border-radius:8px;">' +
        '<div class="mb-2" style="font-size:0.9rem;"><strong>Способ отправки в Telegram:</strong></div>' +
        '<div class="form-check">' +
        '<input class="form-check-input" type="radio" name="tgMode" id="tgModeDirect" value="direct" onchange="tgModeChanged()" ' + (mode==='direct'?'checked':'') + '>' +
        '<label class="form-check-label" for="tgModeDirect">Напрямую (без прокси) — api.telegram.org</label>' +
        '</div>' +
        '<div class="form-check">' +
        '<input class="form-check-input" type="radio" name="tgMode" id="tgModeProxy" value="proxy" onchange="tgModeChanged()" ' + (mode==='proxy'?'checked':'') + '>' +
        '<label class="form-check-label" for="tgModeProxy">Через прокси (HTTP или SOCKS5)</label>' +
        '</div>' +
        '<div id="tgProxyFields" class="ms-4 mt-1 mb-2" style="display:' + (mode==='proxy'?'block':'none') + ';">' +
        '<input type="text" id="tgProxyUrl" class="form-control form-control-sm" placeholder="' + (proxyConfigured ? escapeHtml(proxyMasked) + ' (оставьте пустым чтобы не менять)' : 'socks5://host:port или http://login:pass@host:port') + '">' +
        '<small style="color:var(--muted);">socks5:// требует пакет PySocks (устанавливается вместе с дашбордом)</small>' +
        '</div>' +
        '<div class="form-check">' +
        '<input class="form-check-input" type="radio" name="tgMode" id="tgModeRelay" value="relay" onchange="tgModeChanged()" ' + (mode==='relay'?'checked':'') + '>' +
        '<label class="form-check-label" for="tgModeRelay">Через свой relay/worker (обход блокировки без прокси)</label>' +
        '</div>' +
        '<div id="tgRelayFields" class="ms-4 mt-1 mb-2" style="display:' + (mode==='relay'?'block':'none') + ';">' +
        '<input type="text" id="tgApiBase" class="form-control form-control-sm mb-1" placeholder="https://ваш-домен.example" value="' + escapeHtml(apiBase) + '">' +
        '<input type="text" id="tgApiKey" class="form-control form-control-sm" placeholder="Ключ авторизации — ' + apiKeyHint + ', оставьте пустым чтобы не менять">' +
        '<small style="color:var(--muted);">Запрос уйдёт на &lt;адрес&gt;/bot&lt;токен&gt;/sendMessage?auth=&lt;ключ&gt; — это ДОЛЖЕН быть ваш собственный, доверенный сервер/worker: токен бота уходит на него открытым текстом, как на настоящий api.telegram.org.</small>' +
        '</div>' +
        '<button type="button" class="btn btn-sm btn-outline-primary mt-1" onclick="saveTgTransport()"><i class="bi bi-check-lg"></i> Сохранить способ отправки</button>' +
        '<div id="tgTransportResult" class="mt-2"></div>' +
        '</div>';
    return html;
}

function tgModeChanged() {
    var mode = document.querySelector('input[name="tgMode"]:checked').value;
    document.getElementById('tgProxyFields').style.display = (mode === 'proxy') ? 'block' : 'none';
    document.getElementById('tgRelayFields').style.display = (mode === 'relay') ? 'block' : 'none';
}

async function saveTgTransport() {
    var mode = document.querySelector('input[name="tgMode"]:checked').value;
    var payload = {};
    if (mode === 'direct') {
        payload = {proxy_url: '', api_base: '', api_key: ''};
    } else if (mode === 'proxy') {
        var proxyUrl = document.getElementById('tgProxyUrl').value.trim();
        if (!proxyUrl && !window.__tgProxyConfigured) { alert('Укажите адрес прокси (или переключитесь на "Напрямую")'); return; }
        payload = {api_base: '', api_key: ''};
        if (proxyUrl) { payload.proxy_url = proxyUrl; }
    } else {
        var apiBase = document.getElementById('tgApiBase').value.trim();
        if (!apiBase) { alert('Укажите адрес своего relay/worker'); return; }
        payload = {api_base: apiBase, proxy_url: ''};
        var apiKey = document.getElementById('tgApiKey').value.trim();
        if (apiKey) { payload.api_key = apiKey; }
    }
    var resultDiv = document.getElementById('tgTransportResult');
    resultDiv.innerHTML = '<small style="color:var(--muted);">Сохранение...</small>';
    var r = await fetch('/api/telegram/settings', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload)});
    var d = await r.json();
    if (d.ok) {
        resultDiv.innerHTML = '<small style="color:var(--green);">✅ Сохранено</small>';
        loadTelegramSection();
    } else {
        resultDiv.innerHTML = '<small style="color:var(--red);">❌ ' + escapeHtml(d.error || 'Ошибка') + '</small>';
    }
}

async function addTgChat() {
    var chat_id = document.getElementById('newChatId').value.trim();
    var name = document.getElementById('newChatName').value.trim();
    if (!chat_id) { alert('Введите Chat ID'); return; }
    var r = await fetch('/api/telegram/chats', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({chat_id,name})});
    var d = await r.json();
    if (d.ok) { loadTelegramSection(); } else { alert(d.error); }
}

async function toggleTgChat(id, enabled) {
    await fetch('/api/telegram/chats', {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify({id, enabled})});
    loadTelegramSection();
}

async function deleteTgChat(id) {
    if (!confirm('Удалить получателя?')) return;
    await fetch('/api/telegram/chats?id='+id, {method:'DELETE'});
    loadTelegramSection();
}

async function testTelegram() {
    document.getElementById('tgTestResult').innerHTML = '<small style="color:var(--muted);">Отправка...</small>';
    var r = await fetch('/api/telegram/test', {method:'POST'});
    var d = await r.json();
    document.getElementById('tgTestResult').innerHTML = d.ok ?
        '<small style="color:var(--green);">✅ ' + escapeHtml(d.message) + '</small>' :
        '<small style="color:var(--red);">❌ ' + escapeHtml(d.error) + '</small>';
}

async function loadMailSection() {
    var sec = document.getElementById('mailSection');
    if (!sec) return;
    sec.style.display = 'block';
    {% if logged_in %}
    try {
        var r = await fetch('/api/mail/recipients');
        var recipients = await r.json();
        var rs = await fetch('/api/mail/settings');
        var cfg = await rs.json();
        renderMail(recipients, cfg);
    } catch(e) { console.error(e); }
    {% endif %}
}

function renderMail(recipients, cfg) {
    var enabled = cfg.enabled === "1";
    var smtpOk  = cfg.smtp_configured;

    // Статус бейдж
    var badge = smtpOk && enabled
        ? "<span class='badge bg-success fs-6'>✅ Активен</span>"
        : enabled
            ? "<span class='badge bg-warning fs-6'>⚠ Нет SMTP</span>"
            : "<span class='badge bg-secondary fs-6'>⏸ Выключен</span>";

    // SMTP инфо
    var smtpInfo = smtpOk
        ? "<b>SMTP:</b> <span style='color:var(--green)'>" + escapeHtml(cfg.smtp_server||"?") + ":" + escapeHtml(cfg.smtp_port||"587") + "</span>" +
          (cfg.smtp_user ? " | <b>Логин:</b> " + escapeHtml(cfg.smtp_user) : "") +
          (cfg.monitor_url ? "<br><b>URL:</b> " + escapeHtml(cfg.monitor_url) : "")
        : "<span style='color:var(--red)'>❌ SMTP не настроен</span>";

    // Список получателей
    var rcptHtml = "";
    if (recipients.length) {
        recipients.forEach(function(r) {
            rcptHtml += "<div style='display:flex;justify-content:space-between;align-items:center;" +
                "margin-bottom:4px;padding:6px 10px;background:var(--bg);border-radius:6px;" +
                "opacity:" + (r.enabled ? "1" : "0.5") + "'>" +
                "<div><span class='badge bg-" + (r.enabled ? "success" : "secondary") + " me-1'>" +
                (r.enabled ? "вкл" : "выкл") + "</span>" +
                "<b>" + escapeHtml(r.name || "без имени") + "</b> " +
                "<code style='font-size:11px'>" + escapeHtml(r.email) + "</code></div>" +
                "<div>" +
                "<button class='btn btn-sm btn-outline-" + (r.enabled ? "success" : "secondary") + " me-1' " +
                "onclick='mailToggleRcpt(" + r.id + "," + (r.enabled ? 0 : 1) + ")' title='" + (r.enabled ? "Выключить" : "Включить") + "'>" +
                "<i class='bi bi-" + (r.enabled ? "bell" : "bell-slash") + "'></i></button>" +
                "<button class='btn btn-sm btn-outline-info me-1' onclick='mailEditRcpt(" + r.id + ")' title='Редактировать'>&#9999;</button>" +
                "<button class='btn btn-sm btn-outline-danger' onclick='mailDeleteRcpt(" + r.id + ")' title='Удалить'>&#10005;</button>" +
                "</div></div>";
        });
    } else {
        rcptHtml = "<p style='color:var(--muted)'>Нет получателей</p>";
    }

    var html =
        "<div class='card-header d-flex justify-content-between align-items-center' style='background:rgba(102,126,234,0.05);border-bottom:1px solid var(--border);padding:16px 24px;font-weight:600'>" +
        "<span><i class='bi bi-envelope'></i> Email уведомления</span>" + badge + "</div>" +
        "<div class='card-body'>" +
        "<style>.mfc{color:#fff!important;background:#1a1d27!important;border-color:#2d3239!important;}.mfc::placeholder{color:#6b7280!important;}</style>" +
        "<div id='mailSmtpInfo' class='mb-3 p-3 rounded' style='background:var(--bg)'>" + smtpInfo + "</div>" +
        "<div class='mb-2'><a href='#mailSmtpForm' data-bs-toggle='collapse' class='btn btn-outline-secondary btn-sm w-100'>" +
        "<i class='bi bi-gear'></i> Настроить SMTP сервер</a></div>" +
        "<div class='collapse mb-3' id='mailSmtpForm'>" +
        "<div class='p-3 rounded' style='background:var(--bg);border:1px solid #2d3239'>" +
        "<div class='row g-2'>" +
        "<div class='col-8'><label class='form-label small'>SMTP сервер</label>" +
        "<input type='text' class='form-control form-control-sm mfc' id='mailSmtpServer' value='" + escapeHtml(cfg.smtp_server||"") + "' placeholder='smtp.gmail.com'></div>" +
        "<div class='col-4'><label class='form-label small'>Порт</label>" +
        "<input type='number' class='form-control form-control-sm mfc' id='mailSmtpPort' value='" + escapeHtml(cfg.smtp_port||"587") + "'></div>" +
        "<div class='col-6'><label class='form-label small'>Логин</label>" +
        "<input type='text' class='form-control form-control-sm mfc' id='mailSmtpUser' value='" + escapeHtml(cfg.smtp_user||"") + "' placeholder='user@domain.com'></div>" +
        "<div class='col-6'><label class='form-label small'>Пароль</label>" +
        "<input type='password' class='form-control form-control-sm mfc' id='mailSmtpPass' placeholder='••••••••'></div>" +
        "<div class='col-6'><label class='form-label small'>Имя отправителя</label>" +
        "<input type='text' class='form-control form-control-sm mfc' id='mailFromName' value='" + escapeHtml(cfg.from_name||"TRASSIR Monitor") + "'></div>" +
        "<div class='col-6'><label class='form-label small'>Email отправителя</label>" +
        "<input type='text' class='form-control form-control-sm mfc' id='mailFromAddr' value='" + escapeHtml(cfg.from_addr||"") + "' placeholder='monitor@domain.com'></div>" +
        "<div class='col-12'><label class='form-label small'>URL монитора (для ссылок в письмах)</label>" +
        "<input type='text' class='form-control form-control-sm mfc' id='mailMonitorUrl' value='" + escapeHtml(cfg.monitor_url||"") + "' placeholder='http://192.168.1.100:8080'></div>" +
        "<div class='col-12'><button class='btn btn-primary btn-sm w-100' onclick='mailSaveSmtp()'>" +
        "<i class='bi bi-check-lg'></i> Сохранить SMTP</button></div>" +
        "</div><small class='text-muted d-block mt-2'>Gmail: используйте пароль приложения (App Password)</small>" +
        "</div></div>" +
        "<div class='mb-3'><label class='form-label'>📬 Получатели уведомлений:</label>" +
        "<div id='mailRcptList' class='mb-3' style='max-height:200px;overflow-y:auto'>" + rcptHtml + "</div>" +
        "<div class='input-group input-group-sm mb-2'>" +
        "<input type='email' class='form-control mfc' id='mailNewEmail' placeholder='email@domain.com'>" +
        "<input type='text' class='form-control mfc' id='mailNewName' placeholder='Имя'>" +
        "<button class='btn btn-primary' onclick='mailAddRecipient()'><i class='bi bi-plus-lg'></i></button>" +
        "</div></div>" +
        "<div class='form-check form-switch mb-3'>" +
        "<input class='form-check-input' type='checkbox' id='mailEnabled' " + (enabled ? "checked" : "") + " onchange='mailSaveEnabled()'>" +
        "<label class='form-check-label'><b>Включить Email уведомления</b></label></div>" +
        "<div class='d-flex gap-2'>" +
        "<button class='btn btn-outline-info btn-sm' onclick='mailTest()'><i class='bi bi-send'></i> Тест</button>" +
        "<button class='btn btn-outline-secondary btn-sm' onclick='loadMailSection()'><i class='bi bi-arrow-clockwise'></i> Обновить</button>" +
        "</div><div id='mailResult' class='mt-2' style='display:none'></div>" +
        "</div>";

    document.getElementById('mailBody').innerHTML = html;
}

async function mailSaveSmtp() {
    var data = {
        smtp_server: document.getElementById('mailSmtpServer').value.trim(),
        smtp_port:   document.getElementById('mailSmtpPort').value.trim() || '587',
        smtp_user:   document.getElementById('mailSmtpUser').value.trim(),
        from_name:   document.getElementById('mailFromName').value.trim() || 'TRASSIR Monitor',
        from_addr:   document.getElementById('mailFromAddr').value.trim(),
        monitor_url: document.getElementById('mailMonitorUrl').value.trim()
    };
    var pass = document.getElementById('mailSmtpPass').value;
    if (pass) data.smtp_pass = pass;
    var r = await fetch('/api/mail/settings', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)});
    var d = await r.json();
    mailShowResult(d.ok ? 'SMTP сохранён' : (d.error||'Ошибка'), d.ok ? 'success' : 'danger');
    if (d.ok) loadMailSection();
}

async function mailSaveEnabled() {
    var val = document.getElementById('mailEnabled').checked ? '1' : '0';
    await fetch('/api/mail/settings', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({enabled: val})});
    loadMailSection();
}

async function mailAddRecipient() {
    var email = document.getElementById('mailNewEmail').value.trim();
    var name  = document.getElementById('mailNewName').value.trim();
    if (!email) { alert('Введите email адрес'); return; }
    var r = await fetch('/api/mail/recipients', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({email, name})});
    var d = await r.json();
    if (d.ok) {
        document.getElementById('mailNewEmail').value = '';
        document.getElementById('mailNewName').value  = '';
        loadMailSection();
    } else {
        mailShowResult(d.error, 'danger');
    }
}

async function mailToggleRcpt(id, enabled) {
    await fetch('/api/mail/recipients', {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify({id, enabled})});
    loadMailSection();
}

async function mailEditRcpt(dbId) {
    var r = await fetch('/api/mail/recipients');
    var list = await r.json();
    var rec = list.find(function(x){ return x.id === dbId; });
    if (!rec) return;
    var newEmail = prompt('Email адрес:', rec.email);
    if (newEmail === null) return;
    var newName = prompt('Имя:', rec.name || '');
    if (newName === null) return;
    var data = {id: dbId, name: newName||'', enabled: rec.enabled};
    if (newEmail.trim() && newEmail.trim() !== rec.email) data.email = newEmail.trim();
    var res = await fetch('/api/mail/recipients', {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)});
    var d = await res.json();
    if (d.ok) loadMailSection(); else mailShowResult(d.error, 'danger');
}

async function mailDeleteRcpt(id) {
    if (!confirm('Удалить получателя?')) return;
    await fetch('/api/mail/recipients?id=' + id, {method:'DELETE'});
    loadMailSection();
}

async function mailTest() {
    var e = document.getElementById('mailResult');
    e.style.display = 'block';
    e.className = 'mt-2 alert alert-info';
    e.textContent = 'Отправка тестового письма...';
    var r = await fetch('/api/mail/test', {method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'});
    var d = await r.json();
    e.className = 'mt-2 alert alert-' + (d.ok ? 'success' : 'danger');
    e.textContent = d.ok ? d.message : d.error;
    setTimeout(function(){ e.style.display = 'none'; }, 6000);
}

function mailShowResult(msg, type) {
    var e = document.getElementById('mailResult');
    if (!e) return;
    e.style.display = 'block';
    e.className = 'mt-2 alert alert-' + type;
    e.textContent = msg;
    setTimeout(function(){ e.style.display = 'none'; }, 5000);
}

async function addMailRecipient() {
    var email = document.getElementById('newEmail').value.trim();
    var name = document.getElementById('newEmailName').value.trim();
    if (!email) { alert('Введите email'); return; }
    var r = await fetch('/api/mail/recipients', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({email,name})});
    var d = await r.json();
    if (d.ok) { loadMailSection(); } else { alert(d.error); }
}

async function toggleMailRecipient(id, enabled) {
    await fetch('/api/mail/recipients', {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify({id, enabled})});
    loadMailSection();
}

async function deleteMailRecipient(id) {
    if (!confirm('Удалить получателя?')) return;
    await fetch('/api/mail/recipients?id='+id, {method:'DELETE'});
    loadMailSection();
}

async function testMail() {
    document.getElementById('mailTestResult').innerHTML = '<small style="color:var(--muted);">Отправка...</small>';
    var r = await fetch('/api/mail/test', {method:'POST'});
    var d = await r.json();
    document.getElementById('mailTestResult').innerHTML = d.ok ?
        '<small style="color:var(--green);">✅ ' + escapeHtml(d.message) + '</small>' :
        '<small style="color:var(--red);">❌ ' + escapeHtml(d.error) + '</small>';
}

async function checkForUpdates() {
    var resultDiv = document.getElementById('versionCheckResult');
    resultDiv.innerHTML = '<span style="color:var(--muted);">Проверка...</span>';
    try {
        var r = await fetch('/api/version/check');
        var d = await r.json();
        if (!r.ok) {
            resultDiv.innerHTML = '<span style="color:var(--red);">❌ ' + escapeHtml(d.error || 'Ошибка') + '</span>';
            return;
        }
        var mods = Object.values(d.modules || {});
        if (mods.length === 0) {
            resultDiv.innerHTML = '<span style="color:var(--muted);">Не удалось определить версию ни одного модуля ' +
                '(установлены версией до появления этой проверки — переустановите/обновите через лаунчер, чтобы версия начала фиксироваться)</span>';
            return;
        }
        var lines = mods.map(function(m) {
            return m.up_to_date
                ? '✅ ' + escapeHtml(m.label) + ': последняя версия (' + escapeHtml(m.installed) + ')'
                : '🔄 ' + escapeHtml(m.label) + ': доступно обновление (сейчас ' + escapeHtml(m.installed) + ', актуальный ' + escapeHtml(d.latest_commit) + ')';
        });
        resultDiv.innerHTML = lines.join('<br>');
    } catch (e) {
        resultDiv.innerHTML = '<span style="color:var(--red);">❌ ' + escapeHtml(e.message) + '</span>';
    }
}

// Загружаем статус служб при открытии страницы
loadServices();
</script>
{% endblock %}

{% block footer %}
<div class="text-center mt-4 mb-2" style="font-size:0.75rem; color:var(--muted);">
    TRASSIR Monitor {{ build_info.version }} · обновлено: {{ build_info.mtime }}{% if build_info.commit != '?' %} · коммит: {{ build_info.commit }}{% endif %}
</div>
{% if logged_in %}
<div class="text-center mb-4">
    <button class="btn btn-sm btn-outline-secondary" onclick="checkForUpdates()">
        <i class="bi bi-arrow-repeat"></i> Проверить обновления
    </button>
    <div id="versionCheckResult" class="mt-2" style="font-size:0.85rem;"></div>
</div>
{% endif %}
{% endblock %}
SETTINGSEOF
echo "    ✓ settings.html создан ($(wc -c < $INSTALL_DIR/templates/settings.html) байт)"

# ---------- login.html ----------
echo "  • Создание login.html..."
cat > $INSTALL_DIR/templates/login.html << 'LOGINEOF'
{% extends "base.html" %}
{% block title %}Вход — TRASSIR Monitor{% endblock %}
{% block content %}
<div class="row justify-content-center mt-5">
    <div class="col-md-4">
        <div class="card">
            <div class="card-header">
                <i class="bi bi-lock"></i> Вход в систему
            </div>
            <div class="card-body">
                {% if error %}
                <div class="alert alert-danger mb-3">{{ error }}</div>
                {% endif %}
                <form method="POST">
                    <div class="mb-3">
                        <label class="form-label">Пароль администратора</label>
                        <input type="password" class="form-control" name="password"
                               autofocus placeholder="Введите пароль">
                    </div>
                    <button type="submit" class="btn btn-primary w-100">
                        <i class="bi bi-box-arrow-in-right"></i> Войти
                    </button>
                </form>
                <div class="mt-3 text-center">
                    <a href="/" style="color: var(--muted); font-size: 0.85rem;">
                        ← Вернуться на дашборд
                    </a>
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
LOGINEOF
echo "    ✓ login.html создан ($(wc -c < $INSTALL_DIR/templates/login.html) байт)"

echo ""
echo -e "${GREEN}✅ Все шаблоны созданы${NC}"
echo ""

# ============================================
# ШАГ 6: НАСТРОЙКА СЕРВИСОВ
# ============================================
echo -e "${YELLOW}[6/7] Настройка сервисов...${NC}"
echo ""

# Gunicorn конфигурация
echo "  • Создание конфигурации Gunicorn..."
cat > $INSTALL_DIR/gunicorn_config.py << GUNEOF
# Конфигурация Gunicorn для TRASSIR Monitor v13.0
# Использует gevent для поддержки WebSocket (совместим с Python 3.12+/3.13)

bind = "127.0.0.1:${APP_PORT}"
worker_class = "geventwebsocket.gunicorn.workers.GeventWebSocketWorker"
workers = 1
threads = 4
timeout = 120
keepalive = 5
loglevel = "info"
accesslog = "/opt/trassir-monitor/logs/gunicorn-access.log"
errorlog = "/opt/trassir-monitor/logs/gunicorn-error.log"
GUNEOF
echo "    ✓ gunicorn_config.py создан"

# Systemd сервис
echo "  • Создание systemd сервиса..."
cat > /etc/systemd/system/$SERVICE.service << SERVEOF
[Unit]
Description=TRASSIR Monitor v13.0
Documentation=https://github.com/trassir-monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStartPre=+/bin/bash -c 'chown -R www-data:www-data $INSTALL_DIR/data && chmod 775 $INSTALL_DIR/data'
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --config $INSTALL_DIR/gunicorn_config.py app.app:app
Restart=always
RestartSec=5
KillMode=mixed
StandardOutput=append:$INSTALL_DIR/logs/system.log
StandardError=append:$INSTALL_DIR/logs/system-error.log

[Install]
WantedBy=multi-user.target
SERVEOF
echo "    ✓ systemd сервис создан"

# Nginx drop-in — гарантируем перезапуск nginx после смены IP/сети
echo "  • Настройка nginx для корректной работы при смене IP..."
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/restart-on-network.conf << 'NGINXDROPEOF'
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=5
NGINXDROPEOF
echo "    ✓ nginx drop-in создан"

# Nginx конфигурация
echo "  • Создание конфигурации Nginx..."
cat > /etc/nginx/sites-available/trassir-monitor << NGINXEOF
# Nginx конфигурация для TRASSIR Monitor v13.0
server {
    listen $WEB_PORT default_server;
    listen [::]:$WEB_PORT default_server;
    server_name _;

    # Буферы для заголовков (лечит "400 Bad Request: Request Header Or Cookie Too Large")
    large_client_header_buffers 4 32k;
    client_header_buffer_size 8k;
    
    # Статические файлы
    location /static/ {
        alias $INSTALL_DIR/static/;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
    
    # WebSocket прокси
    location /socket.io/ {
        proxy_pass http://127.0.0.1:${APP_PORT}/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
        proxy_buffering off;
    }
    
    # Основное приложение
    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }
}
NGINXEOF
echo "    ✓ Nginx конфигурация создана"

# Активируем сайт
ln -sf /etc/nginx/sites-available/trassir-monitor /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
echo "    ✓ Сайт активирован"

echo ""
echo -e "${GREEN}✅ Сервисы настроены${NC}"
echo ""

# ============================================
# ШАГ 7: ДЕИНСТАЛЛЯТОР И ЗАПУСК
# ============================================
echo -e "${YELLOW}[7/7] Создание деинсталлятора и запуск...${NC}"
echo ""

# Деинсталлятор
echo "  • Создание деинсталлятора..."
cat > /usr/local/bin/trassir-monitor-uninstall << 'UNEOF'
#!/bin/bash
# ============================================
# Безопасное удаление TRASSIR Monitor
# Удаляет только проект, системные пакеты НЕ трогает
# ============================================

# Живой баг, найденный 2026-09-06: этот heredoc написан с 'UNEOF' в
# кавычках — bash-переменные основного install-скрипта сюда НЕ
# подставляются, они попадают в файл буквально как текст "$INSTALL_DIR".
# Без этой строки деинсталлятор запускался бы с пустым INSTALL_DIR, и
# "rm -rf $INSTALL_DIR" ниже превращался бы в "rm -rf" без аргумента —
# безобидный, но полностью бесполезный no-op: сам деинсталлятор никогда
# реально не удалял папку проекта.
INSTALL_DIR="/opt/trassir-monitor"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     УДАЛЕНИЕ TRASSIR Monitor                 ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Запустите с правами root:${NC}"
    echo -e "  ${YELLOW}sudo trassir-monitor-uninstall${NC}"
    exit 1
fi

echo -e "${YELLOW}Внимание!${NC}"
echo -e "Будут удалены ТОЛЬКО файлы проекта TRASSIR Monitor."
echo -e "Системные пакеты (Python, Nginx, и т.д.) ${GREEN}НЕ трогаются${NC}."
echo ""
echo "Будет удалено:"
echo "  • $INSTALL_DIR (папка проекта)"
echo "  • /etc/systemd/system/trassir-monitor.service"
echo "  • /etc/nginx/sites-available/trassir-monitor"
echo "  • /etc/nginx/sites-enabled/trassir-monitor"
echo "  • /usr/local/bin/trassir-monitor-uninstall (этот скрипт)"
echo ""
echo -e "${GREEN}НЕ будут удалены:${NC}"
echo "  • Python и pip пакеты"
echo "  • Nginx"
echo "  • Другие проекты"
echo ""

read -p "Для подтверждения введите DELETE заглавными буквами: " confirm

if [ "$confirm" != "DELETE" ]; then
    echo -e "${GREEN}Отмена удаления${NC}"
    exit 0
fi

echo ""
echo "Остановка сервиса..."
systemctl stop trassir-monitor 2>/dev/null || true
systemctl disable trassir-monitor 2>/dev/null || true

echo "Удаление конфигурационных файлов..."
rm -f /etc/systemd/system/trassir-monitor.service
rm -f /etc/nginx/sites-enabled/trassir-monitor
rm -f /etc/nginx/sites-available/trassir-monitor
rm -f /etc/systemd/system/nginx.service.d/restart-on-network.conf
rmdir /etc/systemd/system/nginx.service.d 2>/dev/null || true

systemctl daemon-reload
systemctl restart nginx 2>/dev/null || /usr/sbin/nginx -s reload 2>/dev/null || true

echo ""
read -p "Сохранить базу данных перед удалением? (y/N): " save_data

if [[ $save_data =~ ^[Yy]$ ]]; then
    BACKUP_DIR="/root/trassir-monitor-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r $INSTALL_DIR/data "$BACKUP_DIR/" 2>/dev/null
    cp -r $INSTALL_DIR/logs "$BACKUP_DIR/" 2>/dev/null
    echo -e "${GREEN}✅ Данные сохранены в: $BACKUP_DIR${NC}"
fi

echo "Удаление папки проекта..."
rm -rf $INSTALL_DIR

echo "Удаление деинсталлятора..."
rm -f /usr/local/bin/trassir-monitor-uninstall

echo "Удаление команды смены пароля..."
rm -f /usr/local/bin/trassir-monitor-set-password

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  TRASSIR Monitor полностью удалён!           ║${NC}"
echo -e "${GREEN}║  Системные пакеты сохранены.                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
UNEOF

chmod +x /usr/local/bin/trassir-monitor-uninstall
echo "    ✓ Деинсталлятор создан: /usr/local/bin/trassir-monitor-uninstall"

# Смена пароля администратора прямо на сервере, без входа в веб-интерфейс
# (полезно, если пароль забыт и войти в /settings уже нельзя).
echo "  • Установка команды смены пароля..."
cat > /usr/local/bin/trassir-monitor-set-password << 'PWCLIEOF'
#!/bin/bash
# ============================================
# Смена пароля администратора TRASSIR Monitor
# Пишет напрямую в БД — веб-интерфейс не нужен, вход тоже
# ============================================

INSTALL_DIR="/opt/trassir-monitor"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Запустите с правами root:${NC}"
    echo -e "  ${YELLOW}sudo trassir-monitor-set-password${NC}"
    exit 1
fi

if [ ! -f "$INSTALL_DIR/data/trassir.db" ]; then
    echo -e "${RED}База данных не найдена: $INSTALL_DIR/data/trassir.db${NC}"
    echo "TRASSIR Monitor установлен и хотя бы раз запускался?"
    exit 1
fi

echo -e "${YELLOW}Смена пароля администратора TRASSIR Monitor${NC}"
echo ""

while true; do
    read -p "  Новый пароль: " NEW_PASSWORD
    if [ ${#NEW_PASSWORD} -lt 4 ]; then
        echo -e "  ${YELLOW}Слишком короткий пароль (минимум 4 символа), попробуйте снова${NC}"
        continue
    fi
    read -p "  Повторите пароль: " NEW_PASSWORD_CONFIRM
    if [ "$NEW_PASSWORD" != "$NEW_PASSWORD_CONFIRM" ]; then
        echo -e "  ${RED}Пароли не совпадают, попробуйте снова${NC}"
        continue
    fi
    break
done

if TRASSIR_ADMIN_PASSWORD="$NEW_PASSWORD" TRASSIR_DB_PATH="$INSTALL_DIR/data/trassir.db" \
   "$INSTALL_DIR/venv/bin/python3" - <<'PYSETPWEOF'
import os
import sqlite3
from werkzeug.security import generate_password_hash

pw = os.environ["TRASSIR_ADMIN_PASSWORD"]
poll = os.environ.get("TRASSIR_POLL_INTERVAL", "")
conn = sqlite3.connect(os.environ["TRASSIR_DB_PATH"], timeout=10)
conn.execute(
    "INSERT OR REPLACE INTO settings (key, value) VALUES ('admin_password', ?)",
    (generate_password_hash(pw),)
)
if poll:
    conn.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES ('poll_interval', ?)",
        (poll,)
    )
conn.commit()
conn.close()
PYSETPWEOF
then
    echo ""
    echo -e "${GREEN}✓ Пароль обновлён.${NC} Действующие сессии в браузере не сбрасываются —"
    echo "  выйдите и войдите заново, если хотите использовать новый пароль сразу."
else
    echo -e "${RED}Не удалось записать пароль в БД.${NC}"
    exit 1
fi
PWCLIEOF
chmod +x /usr/local/bin/trassir-monitor-set-password
echo "    ✓ Команда создана: trassir-monitor-set-password"

# Настройка ротации логов
echo ""
echo "  • Настройка ротации логов (logrotate)..."
# copytruncate, не create+postrotate-reload: все три systemd-юнита пишут
# через StandardOutput/StandardError=append:<путь> и НЕ объявляют
# ExecReload (обычные print()-скрипты, никакого обработчика SIGHUP для
# переоткрытия лог-файла нет). При стратегии create логротейт
# переименовывает файл и создаёт новый пустой, а уже открытый файловый
# дескриптор процесса продолжает писать в СТАРЫЙ инод (теперь под именем
# system.log.1) — "systemctl reload" в postrotate для юнита без
# ExecReload ничего не делает, `|| true` эту неудачу тихо проглатывает.
# Итог живьём: tail -f logs/system.log (именно то, что советует README)
# показывает пустоту уже после первой же ежедневной ротации, а реальный
# вывод продолжает копиться в переименованном/сжатом файле, который
# процесс не глядя допишет ещё раз следующим циклом ротации — то есть
# РЕАЛЬНЫЙ файл лога не ограничен вообще, просто прячется под чужим
# именем, пока сервис не перезапустят вручную. Подтверждено симуляцией
# перед этим исправлением. copytruncate копирует содержимое и обнуляет
# ТОТ ЖЕ инод на месте — открытый дескриптор процесса ничего не замечает,
# следующая запись уже идёт в свежий файл, без reload/restart.
cat > /etc/logrotate.d/trassir-monitor << 'LOGROTEOF'
/opt/trassir-monitor/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGROTEOF
echo "    ✓ Logrotate настроен (ежедневно, 7 дней, сжатие, copytruncate)"


# Настройка прав доступа
echo ""
echo "  • Настройка прав доступа..."
chown -R www-data:www-data $INSTALL_DIR
chmod -R 755 $INSTALL_DIR
echo "    ✓ Права установлены"

# Запуск сервисов
echo ""
echo "  • Запуск сервисов..."
NGINX_BIN=$(command -v nginx || echo "/usr/sbin/nginx")

# Включаем network-online.target
systemctl enable systemd-networkd-wait-online.service 2>/dev/null || \
systemctl enable NetworkManager-wait-online.service 2>/dev/null || true

# Перезагружаем конфиги systemd
systemctl daemon-reload

# Регистрируем автозапуск
systemctl enable $SERVICE 2>/dev/null || true

# Проверяем что enable сработал
IS_ENABLED=$(systemctl is-enabled $SERVICE 2>/dev/null || echo "unknown")
if [ "$IS_ENABLED" = "enabled" ]; then
    echo "    ✓ Автозапуск при загрузке: включён"
else
    echo "    ⚠ Повторная попытка enable..."
    ln -sf /etc/systemd/system/$SERVICE.service \
           /etc/systemd/system/multi-user.target.wants/$SERVICE.service 2>/dev/null || true
    systemctl daemon-reload
    echo "    ✓ Симлинк создан вручную"
fi

systemctl restart $SERVICE
systemctl restart nginx 2>/dev/null || $NGINX_BIN -s reload 2>/dev/null || true
echo "    ✓ Сервисы запущены"

# Ждём запуска
sleep 5

# ============================================
# ПРИМЕНЯЕМ ПАРОЛЬ АДМИНИСТРАТОРА И ИНТЕРВАЛ ОПРОСА ИЗ ШАГА "ЗАПРОС ПАРАМЕТРОВ"
# ============================================
# app.py — quoted heredoc (см. CLAUDE.md), bash-переменные внутрь него не
# подставляются, поэтому пароль нельзя было передать через сам исходник.
# init_db() кладёт в settings.admin_password хеш дефолтного "admin" (и
# settings.poll_interval="15") при самом первом старте сервиса (уже
# произошло — sleep 5 выше это гарантирует) — здесь заменяем обе записи
# реально введёнными значениями тем же способом, каким settings_page()/
# api_settings() делают это в рантайме. Пароль передаём через переменную
# окружения, а не подставляем в текст Python — heredoc с 'PYSETPWEOF' в
# кавычках, никакой интерполяции bash внутри, поэтому спецсимволы в
# пароле (кавычки, $, обратные слеши) не могут ничего сломать или
# внедриться в код.
#
# Только для свежей установки — на обновлении (IS_UPDATE=1) ADMIN_PASSWORD
# и POLL не определены (см. "СВЕЖАЯ УСТАНОВКА ИЛИ ОБНОВЛЕНИЕ?" в начале
# скрипта), а восстановленная на ШАГе 3 БД уже содержит рабочий пароль и
# интервал — трогать их нечем и незачем.
if [ "$IS_UPDATE" -eq 0 ]; then
    echo "  • Установка пароля администратора и интервала опроса..."
    if TRASSIR_ADMIN_PASSWORD="$ADMIN_PASSWORD" TRASSIR_POLL_INTERVAL="$POLL" \
       TRASSIR_DB_PATH="$INSTALL_DIR/data/trassir.db" \
       "$INSTALL_DIR/venv/bin/python3" - <<'PYSETPWEOF'
import os
import sqlite3
from werkzeug.security import generate_password_hash

pw = os.environ["TRASSIR_ADMIN_PASSWORD"]
poll = os.environ.get("TRASSIR_POLL_INTERVAL", "")
conn = sqlite3.connect(os.environ["TRASSIR_DB_PATH"], timeout=10)
conn.execute(
    "INSERT OR REPLACE INTO settings (key, value) VALUES ('admin_password', ?)",
    (generate_password_hash(pw),)
)
if poll:
    conn.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES ('poll_interval', ?)",
        (poll,)
    )
conn.commit()
conn.close()
PYSETPWEOF
    then
        echo "    ✓ Пароль администратора и интервал опроса установлены"
    else
        echo -e "    ${RED}⚠ Не удалось установить пароль — в системе останется временный пароль 'admin'.${NC}"
        echo -e "    ${YELLOW}Смените его сразу: sudo trassir-monitor-set-password${NC}"
    fi
else
    echo "  • Обновление: пароль администратора и интервал опроса сохранены без изменений."
fi

# ============================================
# ФИКСАЦИЯ УСТАНОВЛЕННОГО КОММИТА (для дашборда/settings и проверки обновлений)
# ============================================
# У этого проекта на сервере НЕТ git-чекаута ни для чего — все install-*.sh
# пишут файлы напрямую на диск через heredoc, а не git clone (см. CLAUDE.md
# "Editing means editing the heredoc directly"). Поэтому единственный
# способ узнать, какой коммит main реально был применён последним —
# спросить у самого GitHub прямо сейчас, пока установка/обновление точно
# идёт с main, и сохранить ответ рядом с БД (data/ — переживает
# обновления, см. "СВЕЖАЯ УСТАНОВКА ИЛИ ОБНОВЛЕНИЕ?" выше). Выполняется
# БЕЗУСЛОВНО (не только на свежей установке) — именно "обновление"
# и есть момент, когда этот файл должен обновиться.
echo ""
echo "  • Определение установленной версии (коммит main на GitHub)..."
# -w дописывает реальный HTTP-код в конец вывода — без этого сбой (сеть,
# лимит запросов GitHub API — 60/час без токена на IP, слишком частое
# тестирование легко в него упирается) выглядел ровно одинаково что при
# 200, что при 403, что при полном отсутствии ответа: пустая строка,
# без единой зацепки, что именно пошло не так.
GITHUB_API_RAW=$(curl -sS --connect-timeout 10 --max-time 15 --retry 2 --retry-delay 3 \
    -H "Accept: application/vnd.github+json" \
    -w '\nHTTPSTATUS:%{http_code}' \
    "https://api.github.com/repos/naumenis-code/TRASSIR-Monitor/commits/main" 2>/dev/null)
GITHUB_HTTP_CODE=$(echo "$GITHUB_API_RAW" | tail -1 | sed 's/HTTPSTATUS://')
GITHUB_BODY=$(echo "$GITHUB_API_RAW" | sed '$d')

LATEST_COMMIT=""
if [ "$GITHUB_HTTP_CODE" = "200" ]; then
    LATEST_COMMIT=$(echo "$GITHUB_BODY" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin)['sha'][:7])
except Exception:
    pass
" 2>/dev/null)
fi

if [ -n "$LATEST_COMMIT" ]; then
    echo "$LATEST_COMMIT" > "$INSTALL_DIR/data/.installed_commit_dashboard"
    echo "    ✓ Версия зафиксирована: $LATEST_COMMIT"
else
    echo -e "    ${YELLOW}⚠ Не удалось определить версию через GitHub API (HTTP ${GITHUB_HTTP_CODE:-нет ответа}) — версия будет показываться как '?'${NC}"
    if [ "$GITHUB_HTTP_CODE" = "403" ]; then
        echo -e "    ${YELLOW}Похоже на лимит запросов к GitHub API (60/час без токена на один IP) — попробуйте обновить позже.${NC}"
    elif [ "$GITHUB_HTTP_CODE" = "000" ] || [ -z "$GITHUB_HTTP_CODE" ]; then
        echo -e "    ${YELLOW}api.github.com не ответил вовсе (не то же самое, что raw.githubusercontent.com,${NC}"
        echo -e "    ${YELLOW}который только что успешно скачал этот же скрипт — разные сервисы GitHub).${NC}"
    fi
    echo -e "    ${YELLOW}(не мешает работе дашборда, только отображению версии/проверке обновлений)${NC}"
fi

# ============================================
# ФИНАЛЬНАЯ ПРОВЕРКА
# ============================================
IP=$(hostname -I | awk '{print $1}')
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$WEB_PORT/ 2>/dev/null || echo "000")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
if [ "$IS_UPDATE" -eq 1 ]; then
echo -e "${GREEN}║   TRASSIR Monitor v13.0 — ОБНОВЛЁН!          ║${NC}"
else
echo -e "${GREEN}║   TRASSIR Monitor v13.0 — УСТАНОВЛЕН!        ║${NC}"
fi
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

if [ ${#_DL_FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}⚠️  Напоминание: ${#_DL_FAILED[@]} статических файлов так и не скачались${NC}"
    echo -e "${RED}   (см. предупреждение выше) — часть интерфейса может не работать.${NC}"
fi
echo ""
echo -e "${BOLD}📍 Веб-интерфейс:${NC}"
echo -e "   ${CYAN}http://${IP}:${WEB_PORT}${NC}"
echo ""
echo -e "${BOLD}📊 HTTP статус:${NC} $HTTP"
echo ""
echo -e "${BOLD}📋 Страницы:${NC}"
echo -e "   🏠 http://${IP}:${WEB_PORT}/ — Дашборд"
echo -e "   📊 http://${IP}:${WEB_PORT}/server/1 — Детальная страница сервера"
echo -e "   ⚙  http://${IP}:${WEB_PORT}/settings — Настройки"
echo ""
echo -e "${BOLD}✅ Функции системы:${NC}"
echo -e "   • Live дашборд с автообновлением через WebSocket"
echo -e "   • Определение ИМЁН конкретных отключённых каналов"
echo -e "   • Алерты при проблемах (диски, камеры, CPU, архив)"
echo -e "   • Алерты не дублируются (один на событие)"
echo -e "   • Московское время (UTC+3)"
echo -e "   • Добавление / редактирование / удаление серверов"
echo -e "   • Графики CPU / камер / архива (6ч, 24ч, 7д)"
echo -e "   • Состояние дисков ✅ / ❌"
echo -e "   • Uptime в днях и часах"
echo -e "   • Время отклика в миллисекундах"
echo -e "   • Настройка порогов алертов"
echo ""
echo -e "${BOLD}🔐 Авторизация:${NC}"
echo -e "   Войти: ${CYAN}http://${IP}:${WEB_PORT}/login${NC}"
if [ "$IS_UPDATE" -eq 1 ]; then
echo -e "   Пароль администратора не менялся (сохранён при обновлении)."
else
echo -e "   Пароль администратора уже установлен (введён на шаге настройки)."
fi
echo -e "   Сменить позже: ${YELLOW}sudo trassir-monitor-set-password${NC}"
echo -e "   или в веб-интерфейсе: Настройки → Смена пароля."
echo ""
echo -e "   Статус сервиса: ${YELLOW}systemctl status $SERVICE${NC}"
echo -e "   Просмотр логов: ${YELLOW}journalctl -u $SERVICE -f${NC}"
echo -e "   Лог камер:      ${YELLOW}tail -f $INSTALL_DIR/logs/collect.log${NC}"
echo ""
echo -e "${BOLD}🗑 Удаление:${NC}"
echo -e "   ${YELLOW}sudo trassir-monitor-uninstall${NC}"
echo -e "   (удаляет только проект, системные пакеты сохраняются)"
echo ""
echo -e "${YELLOW}🔑 Где взять SDK пароль:${NC}"
echo -e "   На сервере TRASSIR откройте:"
echo -e "   Настройки → Веб-сервер → Общие → Пароль SDK"
echo ""
echo -e "${GREEN}============================================${NC}"
echo ""
