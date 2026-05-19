#!/bin/bash
# ============================================
# TRASSIR Monitor v12.0
# Проверено на Debian 12
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
echo -e "${GREEN}║   TRASSIR Monitor v12.0 — Final Complete     ║${NC}"
echo -e "${GREEN}║   Имена каналов • Алерты • Live дашборд      ║${NC}"
echo -e "${GREEN}║   Debian 12/13 • gevent • Python 3.12/3.13  ║${NC}"
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
echo ""

echo -e "${GREEN}✅ Параметры установки:${NC}"
echo -e "   • Порт Web-интерфейса: ${BOLD}$WEB_PORT${NC}"
echo -e "   • Интервал опроса: ${BOLD}${POLL} секунд${NC}"
echo -e "   • Каталог установки: ${BOLD}$INSTALL_DIR${NC}"
echo ""

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
TRASSIR Monitor v12.0 — Основной файл приложения
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
from datetime import datetime
from flask import Flask, jsonify, render_template, request
from flask_cors import CORS
from flask_socketio import SocketIO
import requests
import schedule

# ============================================
# КОНФИГУРАЦИЯ ПРИЛОЖЕНИЯ
# ============================================
BASE_DIR = "/opt/trassir-monitor"
TEMPLATE_DIR = os.path.join(BASE_DIR, "templates")
DB_PATH = os.path.join(BASE_DIR, "data", "trassir.db")
LOG_DIR = os.path.join(BASE_DIR, "logs")

# ============================================
# ИНИЦИАЛИЗАЦИЯ FLASK
# ============================================
app = Flask(__name__, template_folder=TEMPLATE_DIR)

# Секретный ключ для сессий и безопасности
app.secret_key = secrets.token_hex(32)

# Включаем поддержку Cross-Origin Resource Sharing
CORS(app)

# Инициализация SocketIO для WebSocket (используем gevent — поддерживает Python 3.12+/3.13)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="gevent")

# Отключаем предупреждения SSL для самоподписанных сертификатов
requests.packages.urllib3.disable_warnings()

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
    # Индексы для ускорения запросов
    # ============================================
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
            channels_status = {}
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
                        channels_status[ch["name"]] = is_online
                    else:
                        channels_status[ch["name"]] = False
                except Exception as e:
                    channels_status[ch["name"]] = False
                    print(f"  ⚠ Ошибка для канала {ch['name']}: {e}")
                
                # Выводим прогресс для большого количества каналов
                if (i + 1) % 10 == 0:
                    print(f"  Проверено {i + 1}/{len(channels_list)} каналов...")
            
            return {"ok": 1, "channels": channels_status}
        
        except Exception as e:
            return {"ok": 0, "error": str(e)}


# ============================================
# СБОР ДАННЫХ СО ВСЕХ СЕРВЕРОВ
# ============================================

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
        
        # Обрабатываем каждый сервер
        for server in servers:
            server_id = server["id"]
            server_name = server["name"]
            
            # Создаём клиент для этого сервера
            client = TrassirClient({
                "ip": server["ip"],
                "port": server["port"],
                "ssl": bool(server["ssl"]),
                "sdk_password": server["sdk_password"]
            })
            
            # Получаем данные о здоровье
            health = client.get()
            
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
                
                # Инициализируем channels_info (может понадобиться)
                channels_info = None
                offline_names = []
                
                # ============================================
                # ПРОВЕРКА ВОССТАНОВЛЕНИЯ КАНАЛОВ (ВСЕГДА)
                # ============================================
                try:
                    old_alerts = conn.execute(
                        "SELECT id, msg FROM alerts WHERE server_id = ? AND msg LIKE 'Камер офлайн%' AND ack = 0",
                        (server_id,)
                    ).fetchall()
                    
                    if old_alerts:
                        channels_info = client.get_channels_info()
                        if channels_info and channels_info.get("ok"):
                            online_channels = {name for name, status in channels_info["channels"].items() if status}
                            
                            for old_alert in old_alerts:
                                offline_names_in_alert = re.findall(r'#[^,]+', old_alert["msg"])
                                all_online = True
                                for offline_name in offline_names_in_alert:
                                    found_online = False
                                    for online_name in online_channels:
                                        if offline_name.strip() in online_name:
                                            found_online = True
                                            break
                                    if not found_online:
                                        all_online = False
                                
                                if all_online:
                                    conn.execute("UPDATE alerts SET ack = 1 WHERE id = ?", (old_alert["id"],))
                                    conn.commit()
                                    
                                    recovered_list = [n.strip() for n in offline_names_in_alert]
                                    recovery_msg = f"Канал восстановлен: {recovered_list[0]}" if len(recovered_list) == 1 else f"Каналы восстановлены ({len(recovered_list)})"
                                    
                                    dup = conn.execute(
                                        "SELECT id FROM alerts WHERE server_id = ? AND msg = ? AND ts > datetime('now', '+3 hours', '-1 hours')",
                                        (server_id, recovery_msg)
                                    ).fetchone()
                                    
                                    if not dup:
                                        conn.execute(
                                            "INSERT INTO alerts (server_id, ts, level, msg, ack) VALUES (?, datetime('now', '+3 hours'), 'info', ?, 1)",
                                            (server_id, recovery_msg)
                                        )
                                        conn.commit()
                                        print(f"  ✅ {server_name}: {recovery_msg}")
                except Exception as e:
                    print(f"  ⚠ Ошибка при проверке восстановления каналов для {server_name}: {e}")
                
                # ============================================
                # ОПРЕДЕЛЕНИЕ ИМЁН ОТКЛЮЧЁННЫХ КАНАЛОВ
                # ============================================
                
                if health["ch_t"] > health["ch_o"]:
                    print(f"  {server_name}: обнаружен отвал камер ({health['ch_o']}/{health['ch_t']}), запрашиваю имена...")
                    
                    try:
                        if not channels_info or not channels_info.get("ok"):
                            channels_info = client.get_channels_info()
                        
                        if channels_info and channels_info.get("ok"):
                            for channel_name, is_online in channels_info["channels"].items():
                                if not is_online:
                                    offline_names.append(channel_name)
                            
                            print(f"  {server_name}: найдено {len(offline_names)} офлайн-каналов")
                    except Exception as e:
                        print(f"  {server_name}: ошибка получения имён каналов: {e}")
                
                # ============================================
                # ГЕНЕРАЦИЯ АЛЕРТОВ
                # ============================================
                alerts_list = []
                
                if health["disks"] == 0:
                    alerts_list.append(("critical", "Ошибка дисков"))
                
                offline_count = health["ch_t"] - health["ch_o"]
                if offline_count > 0:
                    if offline_names:
                        names_str = ", ".join(offline_names[:5])
                        message = f"Камер офлайн ({offline_count}): {names_str}"
                        if len(offline_names) > 5:
                            message += f" + ещё {len(offline_names) - 5}"
                        alerts_list.append(("warning", message))
                    else:
                        alerts_list.append(("warning", f"Камер офлайн: {offline_count}/{health['ch_t']}"))
                
                cpu_warning = float(settings.get("cpu_warning", 80))
                if health["cpu"] >= cpu_warning:
                    alerts_list.append(("warning", f"CPU: {health['cpu']:.1f}%"))
                
                arch_warning = float(settings.get("archive_warning_days", 14))
                if health["arch"] <= arch_warning:
                    alerts_list.append(("warning", f"Архив: {health['arch']:.1f} дн"))
                
                for level, message in alerts_list:
                    if message.startswith("Камер офлайн"):
                        existing = conn.execute(
                            "SELECT id, msg FROM alerts WHERE server_id = ? AND msg LIKE 'Камер офлайн%' AND ack = 0",
                            (server_id,)
                        ).fetchone()
                        if existing:
                            if existing["msg"] != message:
                                conn.execute(
                                    "UPDATE alerts SET msg = ?, ts = datetime('now', '+3 hours') WHERE id = ?",
                                    (message, existing["id"])
                                )
                                conn.commit()
                                try:
                                    conn.execute(
                                        "DELETE FROM telegram_logs WHERE alert_key = ?",
                                        (str(existing["id"]),)
                                    )
                                    conn.commit()
                                except Exception:
                                    pass  # таблица telegram_logs создаётся при установке telegram-нотифайера
                        else:
                            conn.execute(
                                "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), ?, ?)",
                                (server_id, level, message)
                            )
                            conn.commit()
                    elif message.startswith("CPU:"):
                        # Дедупликация по типу — CPU меняется каждый опрос, ищем по префиксу
                        existing = conn.execute(
                            "SELECT id, msg FROM alerts WHERE server_id = ? AND msg LIKE 'CPU:%' AND ack = 0",
                            (server_id,)
                        ).fetchone()
                        if existing:
                            # Обновляем значение если изменилось
                            if existing["msg"] != message:
                                conn.execute(
                                    "UPDATE alerts SET msg = ?, ts = datetime('now', '+3 hours') WHERE id = ?",
                                    (message, existing["id"])
                                )
                                conn.commit()
                        else:
                            conn.execute(
                                "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), ?, ?)",
                                (server_id, level, message)
                            )
                            conn.commit()
                    elif message.startswith("Архив:"):
                        # Дедупликация по типу — глубина архива меняется, ищем по префиксу
                        existing = conn.execute(
                            "SELECT id, msg FROM alerts WHERE server_id = ? AND msg LIKE 'Архив:%' AND ack = 0",
                            (server_id,)
                        ).fetchone()
                        if existing:
                            if existing["msg"] != message:
                                conn.execute(
                                    "UPDATE alerts SET msg = ?, ts = datetime('now', '+3 hours') WHERE id = ?",
                                    (message, existing["id"])
                                )
                                conn.commit()
                        else:
                            conn.execute(
                                "INSERT INTO alerts (server_id, ts, level, msg) VALUES (?, datetime('now', '+3 hours'), ?, ?)",
                                (server_id, level, message)
                            )
                            conn.commit()
                    else:
                        # Остальные алерты (диски) — точное совпадение
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
                updates.append({
                    "id": server_id,
                    "name": server_name,
                    "ip": server["ip"],
                    "ok": 0,
                    "alerts": 0
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
    
    # Первый сбор через 5 секунд после старта
    time.sleep(5)
    collect()
    
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
        
        servers_data.append({
            "s": dict(server),
            "h": health_data,
            "a": alerts_count
        })
    
    conn.close()
    
    return render_template(
        "dashboard.html",
        servers=servers_data,
        stats=stats
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
    
    return render_template(
        "server.html",
        server=dict(server),
        history=[dict(h) for h in history],
        cur=dict(current) if current else None,
        alerts_active=[dict(a) for a in alerts_active],
        alerts_history=[dict(a) for a in alerts_history]
    )


@app.route("/settings")
def settings_page():
    """
    Страница настроек системы.
    Позволяет:
    - Изменять параметры мониторинга (интервал, пороги)
    - Просматривать и удалять серверы
    """
    conn = get_db()
    
    # Все серверы
    servers = conn.execute(
        "SELECT * FROM servers ORDER BY name"
    ).fetchall()
    
    # Все настройки
    settings_dict = dict(conn.execute(
        "SELECT key, value FROM settings"
    ).fetchall())
    
    conn.close()
    
    return render_template(
        "settings.html",
        servers=[dict(s) for s in servers],
        settings=settings_dict
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


@app.route("/api/hist/<int:server_id>")
def api_history(server_id):
    """
    API: получить историю здоровья сервера.
    
    Параметры:
        h (опционально): количество часов (по умолчанию 24)
    
    Используется для построения графиков.
    """
    hours = request.args.get("h", 24, type=int)
    
    conn = get_db()
    history = conn.execute("""
        SELECT * FROM health 
        WHERE server_id = ? 
        AND ts > datetime('now', '+3 hours', ?)
        ORDER BY ts
    """, (server_id, f'-{hours} hours')).fetchall()
    conn.close()
    
    return jsonify([dict(h) for h in history])


@app.route("/api/servers", methods=["GET", "POST", "PUT", "DELETE"])
def api_servers():
    """
    API для управления серверами.
    
    GET    — список всех серверов
    POST   — добавить новый сервер
    PUT    — изменить существующий сервер
    DELETE — удалить сервер
    """
    conn = get_db()
    
    if request.method == "GET":
        servers = conn.execute(
            "SELECT * FROM servers ORDER BY name"
        ).fetchall()
        conn.close()
        return jsonify([dict(s) for s in servers])
    
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


@app.route("/api/ack/<int:server_id>", methods=["POST"])
@app.route("/api/alerts/<int:server_id>/ack", methods=["POST"])
def acknowledge_alerts(server_id):
    """
    API: подтвердить (сбросить) все активные алерты для сервера.
    """
    conn = get_db()
    conn.execute(
        "UPDATE alerts SET ack = 1 WHERE server_id = ? AND ack = 0",
        (server_id,)
    )
    conn.commit()
    conn.close()
    
    return jsonify({"ok": 1, "message": "Алерты подтверждены"})


@app.route("/api/settings", methods=["GET", "POST"])
def api_settings():
    """
    API для работы с настройками.
    
    GET  — получить все настройки
    POST — обновить настройки (ключ-значение)
    """
    conn = get_db()
    
    if request.method == "GET":
        settings_dict = dict(conn.execute(
            "SELECT key, value FROM settings"
        ).fetchall())
        conn.close()
        return jsonify(settings_dict)
    
    elif request.method == "POST":
        data = request.json
        for key, value in data.items():
            conn.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                (key, str(value))
            )
        conn.commit()
        conn.close()
        return jsonify({"ok": 1, "message": "Настройки сохранены"})


@app.route("/test-connection", methods=["POST"])
def test_connection():
    """
    API: проверить подключение к серверу TRASSIR.
    Используется кнопкой "Проверить" в форме добавления сервера.
    """
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
# ЗАПУСК ПРИЛОЖЕНИЯ
# ============================================

if __name__ != "__main__":
    # Вывод при запуске через gunicorn
    print("=" * 60)
    print("  TRASSIR Monitor v12.0")
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

_dl() {
    local url="$1" dest="$2" name="$3"
    if curl -sL --connect-timeout 15 --retry 2 -o "$dest" "$url" 2>/dev/null && [ -s "$dest" ]; then
        echo "    ✓ $name ($(wc -c < "$dest") байт)"
    else
        echo "    ⚠ Не удалось скачать $name"
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
            background: var(--bg);
            border: 1px solid var(--border);
            color: var(--txt);
            border-radius: 8px;
            padding: 10px 14px;
        }
        
        .form-control:focus {
            border-color: var(--acc);
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.2);
            color: #fff;
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
            <a href="/settings" class="btn btn-outline-light btn-sm ms-3" title="Настройки">
                <i class="bi bi-gear"></i>
            </a>
        </div>
    </nav>
    
    <!-- Основной контент -->
    <div class="container mt-4">
        {% block content %}{% endblock %}
    </div>
    
    <!-- Bootstrap JS (локальный) -->
    <script src="/static/bootstrap.bundle.min.js"></script>
    
    <!-- Скрипты -->
    <script>
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
        <button class="btn btn-sm btn-primary" data-bs-toggle="modal" data-bs-target="#addModal">
            <i class="bi bi-plus-lg"></i> Добавить сервер
        </button>
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
                        <button class="btn btn-sm btn-outline-warning edit-btn"
                                data-id="{{ s.s.id }}"
                                data-name="{{ s.s.name }}"
                                data-ip="{{ s.s.ip }}"
                                data-port="{{ s.s.port }}"
                                data-ssl="{{ s.s.ssl }}">
                            <i class="bi bi-pencil"></i>
                        </button>
                        <a href="/server/{{ s.s.id }}" class="btn btn-sm btn-outline-info">
                            <i class="bi bi-graph-up"></i>
                        </a>
                        <button class="btn btn-sm btn-outline-danger" onclick="deleteServer({{ s.s.id }})">
                            <i class="bi bi-trash"></i>
                        </button>
                    </div>
                    
                </div>
            </div>
            {% endfor %}
        {% else %}
            <!-- Нет серверов -->
            <div class="text-center py-5">
                <i class="bi bi-inbox" style="font-size: 4rem; color: var(--muted);"></i>
                <h4 class="mt-3" style="color: var(--muted);">Нет добавленных серверов</h4>
                <p style="color: var(--muted);">Добавьте сервер TRASSIR для начала мониторинга</p>
                <button class="btn btn-primary btn-lg mt-3" data-bs-toggle="modal" data-bs-target="#addModal">
                    <i class="bi bi-plus-lg"></i> Добавить сервер
                </button>
            </div>
        {% endif %}
    </div>
</div>

<!-- ============================================ -->
<!-- ПЛАВАЮЩАЯ КНОПКА ДОБАВЛЕНИЯ                   -->
<!-- ============================================ -->
<button class="btn btn-primary position-fixed bottom-0 end-0 m-4 rounded-circle shadow-lg"
        style="width: 56px; height: 56px; z-index: 1000;"
        data-bs-toggle="modal" data-bs-target="#addModal"
        title="Добавить сервер">
    <i class="bi bi-plus-lg fs-4"></i>
</button>

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
                (result.error || 'Неизвестная ошибка') +
                '</div>';
        }
    } catch (err) {
        resultDiv.innerHTML = '<div class="alert alert-danger">Ошибка: ' + err.message + '</div>';
    }
}
</script>
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
                    <button class="btn btn-outline-light active" onclick="loadHistory(6)">6ч</button>
                    <button class="btn btn-outline-light" onclick="loadHistory(24)">24ч</button>
                    <button class="btn btn-outline-light" onclick="loadHistory(168)">7д</button>
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
                <button class="btn btn-sm btn-outline-success" onclick="acknowledgeAlerts()">
                    <i class="bi bi-check-all"></i> Сбросить все
                </button>
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
                        <div>{{ alert.msg }}</div>
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
                {% else %}
                    <div class="text-center py-4">
                        <i class="bi bi-check-circle" style="font-size: 3rem; color: var(--green);"></i>
                        <p class="mt-2" style="color: var(--muted);">Нет активных алертов</p>
                    </div>
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

function loadHistory(hours) {
    fetch('/api/hist/{{ server.id }}?h=' + hours)
        .then(function(response) { return response.json(); })
        .then(function(data) {
            var labels = data.map(function(item) {
                return new Date(item.ts).toLocaleTimeString('ru-RU');
            });
            
            var ctx = document.getElementById('historyChart').getContext('2d');
            
            if (historyChart) {
                historyChart.destroy();
            }
            
            historyChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [
                        {
                            label: 'CPU %',
                            data: data.map(function(item) { return item.cpu; }),
                            borderColor: '#667eea',
                            backgroundColor: 'rgba(102, 126, 234, 0.1)',
                            fill: true,
                            tension: 0.4,
                            borderWidth: 2
                        },
                        {
                            label: 'Камеры онлайн',
                            data: data.map(function(item) { return item.ch_online; }),
                            borderColor: '#10b981',
                            backgroundColor: 'rgba(16, 185, 129, 0.1)',
                            fill: true,
                            tension: 0.4,
                            borderWidth: 2,
                            yAxisID: 'y1'
                        },
                        {
                            label: 'Архив (дни)',
                            data: data.map(function(item) { return item.arch; }),
                            borderColor: '#f59e0b',
                            backgroundColor: 'rgba(245, 158, 11, 0.1)',
                            fill: true,
                            tension: 0.4,
                            borderWidth: 2,
                            yAxisID: 'y2'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    plugins: {
                        legend: {
                            labels: {
                                color: '#d1d5db'
                            }
                        }
                    },
                    scales: {
                        y: {
                            type: 'linear',
                            display: true,
                            position: 'left',
                            title: {
                                display: true,
                                text: 'CPU %',
                                color: '#667eea'
                            },
                            grid: {
                                color: 'rgba(255, 255, 255, 0.05)'
                            },
                            ticks: {
                                color: '#6b7280'
                            }
                        },
                        y1: {
                            type: 'linear',
                            display: true,
                            position: 'right',
                            title: {
                                display: true,
                                text: 'Камеры',
                                color: '#10b981'
                            },
                            grid: {
                                drawOnChartArea: false
                            },
                            ticks: {
                                color: '#6b7280'
                            }
                        },
                        y2: {
                            type: 'linear',
                            display: false,
                            position: 'right',
                            grid: {
                                drawOnChartArea: false
                            }
                        },
                        x: {
                            ticks: {
                                color: '#6b7280',
                                maxTicksLimit: 10
                            },
                            grid: {
                                color: 'rgba(255, 255, 255, 0.05)'
                            }
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

// Запуск
loadHistory(24);
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
    /* Исправление цвета текста в полях ввода на странице настроек */
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
    
    /* Стили для placeholder (подсказок в полях) */
    #settingsForm .form-control::placeholder {
        color: #6b7280 !important;
        opacity: 1 !important;
    }
    
    /* Стили для маленького текста под полями */
    #settingsForm .text-muted {
        color: #6b7280 !important;
    }
</style>

<!-- Навигация -->
<nav class="mb-4">
    <a href="/" class="btn btn-outline-light btn-sm">
        <i class="bi bi-arrow-left"></i> Назад на дашборд
    </a>
</nav>

<h2 class="mb-4"><i class="bi bi-gear"></i> Настройки системы</h2>

<div class="row g-4">
    <!-- Параметры мониторинга -->
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
                        <small class="text-muted">Сколько дней хранить историю и алерты</small>
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
    </div>
    
    <!-- Список серверов -->
    <div class="col-lg-6">
        <div class="card">
            <div class="card-header">
                <i class="bi bi-hdd-stack"></i> Список серверов
            </div>
            <div class="card-body">
                {% if servers %}
                    <table class="table table-dark table-hover">
                        <thead>
                            <tr>
                                <th>Название</th>
                                <th>IP адрес</th>
                                <th>Порт</th>
                                <th>Действия</th>
                            </tr>
                        </thead>
                        <tbody>
                            {% for server in servers %}
                            <tr>
                                <td>{{ server.name }}</td>
                                <td>{{ server.ip }}</td>
                                <td>{{ server.port }}</td>
                                <td>
                                    <button class="btn btn-sm btn-danger" 
                                            onclick="if(confirm('Удалить сервер {{ server.name }}?'))fetch('/api/servers?id={{ server.id }}',{method:'DELETE'}).then(function(){location.reload()})">
                                        <i class="bi bi-trash"></i> Удалить
                                    </button>
                                </td>
                            </tr>
                            {% endfor %}
                        </tbody>
                    </table>
                {% else %}
                    <p class="text-muted text-center py-3">Нет добавленных серверов</p>
                {% endif %}
            </div>
        </div>
    </div>
</div>

{% endblock %}

{% block scripts %}
<script>
document.getElementById('settingsForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    var formData = new FormData(this);
    var data = Object.fromEntries(formData);
    
    var response = await fetch('/api/settings', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(data)
    });
    
    if (response.ok) {
        alert('Настройки сохранены! Изменения вступят в силу при следующем опросе.');
    } else {
        alert('Ошибка при сохранении настроек');
    }
});
</script>
{% endblock %}
SETTINGSEOF
echo "    ✓ settings.html создан ($(wc -c < $INSTALL_DIR/templates/settings.html) байт)"

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
# Конфигурация Gunicorn для TRASSIR Monitor v12.0
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
Description=TRASSIR Monitor v12.0
Documentation=https://github.com/trassir-monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
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
# Nginx конфигурация для TRASSIR Monitor v12.0
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

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  TRASSIR Monitor полностью удалён!           ║${NC}"
echo -e "${GREEN}║  Системные пакеты сохранены.                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
UNEOF

chmod +x /usr/local/bin/trassir-monitor-uninstall
echo "    ✓ Деинсталлятор создан: /usr/local/bin/trassir-monitor-uninstall"

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

# Включаем network-online.target чтобы сервисы ждали полного поднятия сети
systemctl enable systemd-networkd-wait-online.service 2>/dev/null || \
systemctl enable NetworkManager-wait-online.service 2>/dev/null || true

systemctl daemon-reload
systemctl enable $SERVICE
systemctl restart $SERVICE
systemctl restart nginx 2>/dev/null || $NGINX_BIN -s reload 2>/dev/null || true
echo "    ✓ Сервисы запущены"

# Ждём запуска
sleep 5

# ============================================
# ФИНАЛЬНАЯ ПРОВЕРКА
# ============================================
IP=$(hostname -I | awk '{print $1}')
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$WEB_PORT/ 2>/dev/null || echo "000")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║   TRASSIR Monitor v12.0 — УСТАНОВЛЕН!        ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
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
echo -e "${BOLD}🔧 Управление:${NC}"
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
