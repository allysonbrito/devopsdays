#!/usr/bin/env python3
"""
Monitor de Conectividade - DevOpsDays (Versão Corrigida)
Aplicação Flask que monitora conectividade HTTP de múltiplos targets
"""

import json
import time
import socket
from flask import Flask, jsonify, render_template_string
from threading import Thread
import requests
import urllib3
from requests.exceptions import (
    ConnectionError, Timeout, TooManyRedirects, 
    RequestException, HTTPError
)

# Desabilita warnings SSL para requests HTTPS
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

app = Flask(__name__)

# Carrega lista de targets do arquivo de configuração
try:
    with open('/app/config/ips.json', 'r') as f:
        config = json.load(f)
    targets = config['targets']
    print(f"Carregados {len(targets)} targets para monitoramento")
except Exception as e:
    print(f"Erro ao carregar configuração: {e}")
    targets = []

# Dicionário para armazenar status atual
status = {}


def ping_target(ip):
    """
    Verifica conectividade HTTP/HTTPS de forma mais rigorosa
    Retorna tuple: (is_online, status_detail, response_time)
    """
    start_time = time.time()
    
    # 1. Primeiro tenta HTTP (mais comum para APIs/sites)
    try:
        response = requests.get(
            f"http://{ip}", 
            timeout=3,  # Timeout mais rigoroso
            allow_redirects=True,
            headers={'User-Agent': 'DevOpsDays-Monitor/1.0'}
        )
        response_time = round((time.time() - start_time) * 1000, 2)
        
        # Considera online apenas se realmente funcional
        if 200 <= response.status_code < 400:
            return True, f"HTTP OK ({response.status_code})", response_time
        elif 400 <= response.status_code < 500:
            return False, f"HTTP Client Error ({response.status_code})", response_time
        else:
            return False, f"HTTP Server Error ({response.status_code})", response_time
            
    except ConnectionError:
        # Servidor realmente inacessível - continua para HTTPS
        pass
    except Timeout:
        return False, "HTTP Timeout", round((time.time() - start_time) * 1000, 2)
    except (RequestException, Exception) as e:
        # Log específico seria útil em produção
        pass
    
    # 2. Se HTTP falhou, tenta HTTPS
    start_time = time.time()
    try:
        response = requests.get(
            f"https://{ip}", 
            timeout=3,
            verify=False,  # Ignora SSL inválido apenas para teste de conectividade
            allow_redirects=True,
            headers={'User-Agent': 'DevOpsDays-Monitor/1.0'}
        )
        response_time = round((time.time() - start_time) * 1000, 2)
        
        if 200 <= response.status_code < 400:
            return True, f"HTTPS OK ({response.status_code})", response_time
        elif 400 <= response.status_code < 500:
            return False, f"HTTPS Client Error ({response.status_code})", response_time
        else:
            return False, f"HTTPS Server Error ({response.status_code})", response_time
            
    except ConnectionError:
        # Servidor inacessível via HTTPS também
        pass
    except Timeout:
        return False, "HTTPS Timeout", round((time.time() - start_time) * 1000, 2)
    except (RequestException, Exception):
        pass
    
    # 3. Como último recurso, testa conectividade TCP básica
    # Apenas para serviços que podem não responder HTTP mas estão "up"
    start_time = time.time()
    for port in [80, 443]:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)  # Timeout ainda mais baixo para TCP
            result = sock.connect_ex((ip, port))
            sock.close()
            
            if result == 0:
                response_time = round((time.time() - start_time) * 1000, 2)
                return True, f"TCP Port {port} Open (No HTTP)", response_time
                
        except socket.error:
            pass
    
    # Se chegou até aqui, o servidor está realmente offline
    total_time = round((time.time() - start_time) * 1000, 2)
    return False, "Connection Failed", total_time


def monitor_loop():
    """
    Loop principal de monitoramento melhorado que roda em background
    Verifica todos os targets a cada 10 segundos
    """
    print("🔍 Iniciando loop de monitoramento melhorado...")
    
    while True:
        print(f"🔄 Verificando {len(targets)} targets...")
        
        for i, target in enumerate(targets, 1):
            ip = target['ip']
            name = target['name']
            
            # Usa a função melhorada que retorna mais detalhes
            is_online, status_detail, response_time = ping_target(ip)
            
            # Atualiza status com informações detalhadas
            status[ip] = {
                'name': name,
                'status': 'online' if is_online else 'offline',
                'status_detail': status_detail,
                'last_check': time.strftime('%Y-%m-%d %H:%M:%S'),
                'response_time': response_time if is_online else None
            }
            
            # Log mais detalhado do resultado
            status_emoji = '✅' if is_online else '❌'
            response_info = f" ({response_time}ms)" if is_online else ""
            print(f"  {i:2d}. {status_emoji} {name} ({ip}){response_info} - {status_detail}")
        
        # Estatísticas rápidas
        online_count = sum(1 for s in status.values() if s['status'] == 'online')
        offline_count = len(status) - online_count
        print(f"📊 Status: {online_count} online, {offline_count} offline")
        print("-" * 50)
        
        # Aguarda próxima verificação
        time.sleep(10)


@app.route('/')
def index():
    """Página principal com interface de monitoramento"""
    return render_template_string('''
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🔗 Monitor de Conectividade - DevOpsDays</title>
    <style>
        * { 
            box-sizing: border-box; 
            margin: 0; 
            padding: 0; 
        }
        
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container { 
            max-width: 1000px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.95); 
            padding: 30px; 
            border-radius: 15px; 
            box-shadow: 0 10px 40px rgba(0,0,0,0.15);
            backdrop-filter: blur(10px);
        }
        
        header {
            text-align: center;
            margin-bottom: 40px;
        }
        
        h1 { 
            color: #2c3e50; 
            font-size: 2.5em; 
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.1);
        }
        
        .subtitle {
            color: #7f8c8d;
            font-size: 1.1em;
            margin-bottom: 20px;
        }
        
        .last-update {
            color: #95a5a6;
            font-size: 0.9em;
        }
        
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .stat {
            text-align: center; 
            padding: 20px;
            background: rgba(255,255,255,0.9); 
            border-radius: 12px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            transition: transform 0.2s ease;
        }
        
        .stat:hover {
            transform: translateY(-2px);
        }
        
        .stat-number { 
            font-size: 2.5em; 
            font-weight: bold; 
            margin-bottom: 5px;
            display: block;
        }
        
        .stat-label { 
            color: #666; 
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .online-count { color: #27ae60; }
        .offline-count { color: #e74c3c; }
        .total-count { color: #3498db; }
        
        .targets-grid {
            display: grid;
            gap: 15px;
        }
        
        .target { 
            display: flex; 
            justify-content: space-between; 
            align-items: center; 
            padding: 25px; 
            border-radius: 12px; 
            border-left: 6px solid #bdc3c7;
            transition: all 0.3s ease;
            background: rgba(255,255,255,0.9);
            box-shadow: 0 4px 12px rgba(0,0,0,0.08);
        }
        
        .target:hover {
            transform: translateY(-3px);
            box-shadow: 0 8px 20px rgba(0,0,0,0.15);
        }
        
        .target.online { 
            border-left-color: #27ae60; 
            background: linear-gradient(90deg, rgba(39,174,96,0.1) 0%, rgba(255,255,255,0.9) 100%);
        }
        
        .target.offline { 
            border-left-color: #e74c3c; 
            background: linear-gradient(90deg, rgba(231,76,60,0.1) 0%, rgba(255,255,255,0.9) 100%);
        }
        
        .target-info h3 { 
            margin-bottom: 8px; 
            color: #2c3e50; 
            font-size: 1.4em; 
        }
        
        .target-info .url { 
            color: #7f8c8d; 
            font-family: 'Monaco', 'Courier New', monospace; 
            font-size: 1em;
            margin-bottom: 8px;
        }
        
        .target-meta {
            display: flex;
            gap: 15px;
            font-size: 0.85em;
            color: #95a5a6;
            flex-wrap: wrap;
        }
        
        .status-detail {
            font-weight: 500;
            color: #34495e;
            font-size: 0.9em;
            margin-top: 4px;
        }
        
        .status-badge { 
            padding: 12px 24px; 
            border-radius: 25px; 
            color: white; 
            font-weight: bold; 
            font-size: 1.1em;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.2);
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .status-badge.online { 
            background: linear-gradient(45deg, #27ae60, #2ecc71); 
        }
        
        .status-badge.offline { 
            background: linear-gradient(45deg, #e74c3c, #c0392b); 
        }
        
        .loading {
            text-align: center;
            padding: 40px;
            color: #7f8c8d;
        }
        
        .error {
            text-align: center;
            padding: 40px;
            color: #e74c3c;
            background: rgba(231,76,60,0.1);
            border-radius: 8px;
            margin: 20px 0;
        }
        
        footer {
            text-align: center; 
            margin-top: 40px; 
            padding: 20px 0;
            border-top: 1px solid rgba(0,0,0,0.1);
            color: #7f8c8d; 
            font-size: 0.9em;
        }
        
        @media (max-width: 768px) {
            .target { 
                flex-direction: column; 
                text-align: center; 
                gap: 15px; 
            }
            
            h1 { font-size: 2em; }
            
            .target-meta {
                justify-content: center;
            }
        }
        
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.7; }
            100% { opacity: 1; }
        }
        
        .updating {
            animation: pulse 1s infinite;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔗 Monitor de Conectividade</h1>
            <p class="subtitle">Monitoramento rigoroso de conectividade HTTP/HTTPS</p>
            <p class="last-update">Última atualização: <span id="last-update">Carregando...</span></p>
        </header>
        
        <div class="stats">
            <div class="stat">
                <span class="stat-number online-count" id="online-count">-</span>
                <span class="stat-label">Online</span>
            </div>
            <div class="stat">
                <span class="stat-number offline-count" id="offline-count">-</span>
                <span class="stat-label">Offline</span>
            </div>
            <div class="stat">
                <span class="stat-number total-count" id="total-count">-</span>
                <span class="stat-label">Total</span>
            </div>
        </div>
        
        <div class="targets-grid" id="targets">
            <div class="loading">
                <h3>🔄 Carregando dados...</h3>
                <p>Aguarde enquanto verificamos a conectividade</p>
            </div>
        </div>
        
        <footer>
            <p>🚀 <strong>DevOpsDays</strong> | Atualização automática a cada 5 segundos</p>
            <p>Conectividade verificada via HTTP, HTTPS e TCP | Versão 2.0 - Detecção Aprimorada</p>
        </footer>
    </div>
    
    <script>
        let isUpdating = false;
        
        function formatTimestamp() {
            return new Date().toLocaleString('pt-BR');
        }
        
        function updateStatus() {
            if (isUpdating) return;
            
            isUpdating = true;
            const container = document.getElementById('targets');
            container.classList.add('updating');
            
            fetch('/api/status')
                .then(response => {
                    if (!response.ok) throw new Error('Network response was not ok');
                    return response.json();
                })
                .then(data => {
                    container.innerHTML = '';
                    container.classList.remove('updating');
                    
                    let onlineCount = 0;
                    let offlineCount = 0;
                    
                    // Se não há dados ainda
                    if (Object.keys(data).length === 0) {
                        container.innerHTML = '<div class="loading"><h3>⏳ Primeira verificação em andamento...</h3></div>';
                        return;
                    }
                    
                    Object.keys(data).forEach(ip => {
                        const target = data[ip];
                        if (target.status === 'online') onlineCount++;
                        else offlineCount++;
                        
                        const div = document.createElement('div');
                        div.className = `target ${target.status}`;
                        
                        const responseTimeInfo = target.response_time ? 
                            `<span>⚡ ${target.response_time}ms</span>` : '';
                        
                        const statusDetailInfo = target.status_detail ? 
                            `<div class="status-detail">📋 ${target.status_detail}</div>` : '';
                        
                        div.innerHTML = `
                            <div class="target-info">
                                <h3>${target.name}</h3>
                                <div class="url">${ip}</div>
                                <div class="target-meta">
                                    <span>🕒 ${target.last_check}</span>
                                    ${responseTimeInfo}
                                </div>
                                ${statusDetailInfo}
                            </div>
                            <div class="status-badge ${target.status}">
                                ${target.status === 'online' ? '🟢 ONLINE' : '🔴 OFFLINE'}
                            </div>
                        `;
                        container.appendChild(div);
                    });
                    
                    // Atualiza estatísticas
                    document.getElementById('online-count').textContent = onlineCount;
                    document.getElementById('offline-count').textContent = offlineCount;
                    document.getElementById('total-count').textContent = onlineCount + offlineCount;
                    document.getElementById('last-update').textContent = formatTimestamp();
                })
                .catch(error => {
                    console.error('Erro ao carregar dados:', error);
                    container.classList.remove('updating');
                    container.innerHTML = `
                        <div class="error">
                            <h3>❌ Erro ao carregar dados</h3>
                            <p>Tentando reconectar... (${error.message})</p>
                        </div>
                    `;
                })
                .finally(() => {
                    isUpdating = false;
                });
        }
        
        // Atualiza imediatamente e depois a cada 5 segundos
        updateStatus();
        setInterval(updateStatus, 5000);
        
        // Atualiza timestamp a cada segundo
        setInterval(() => {
            if (!isUpdating) {
                document.getElementById('last-update').textContent = formatTimestamp();
            }
        }, 1000);
    </script>
</body>
</html>
    ''')


@app.route('/api/status')
def get_status():
    """
    API endpoint que retorna o status atual de todos os targets
    Retorna JSON com informações detalhadas de conectividade
    """
    return jsonify(status)


@app.route('/api/targets')
def get_targets():
    """API endpoint que retorna a lista de targets configurados"""
    return jsonify({
        'targets': targets,
        'count': len(targets)
    })


@app.route('/health')
def health():
    """Health check endpoint para Kubernetes probes"""
    online_count = sum(1 for s in status.values() if s['status'] == 'online')
    
    return jsonify({
        "status": "healthy",
        "targets_total": len(targets),
        "targets_online": online_count,
        "targets_offline": len(status) - online_count,
        "uptime": time.time() - start_time,
        "version": "2.0.0"
    })


if __name__ == '__main__':
    print("🚀 Iniciando Monitor de Conectividade - Versão Aprimorada...")
    print(f"📝 Versão: 2.0.0")
    print(f"🎯 Targets configurados: {len(targets)}")
    print("🔧 Melhorias: Detecção mais rigorosa, timeouts otimizados, logging detalhado")
    
    # Marca tempo de início
    start_time = time.time()
    
    # Inicia thread de monitoramento em background
    monitor_thread = Thread(target=monitor_loop, daemon=True)
    monitor_thread.start()
    print("✅ Thread de monitoramento iniciada")
    
    # Aguarda primeira verificação
    print("⏳ Aguardando primeira verificação...")
    time.sleep(3)
    
    print("🌐 Servidor Flask iniciado em http://0.0.0.0:8080")
    print("📊 Acesse a interface web para ver o monitoramento em tempo real")
    print("-" * 60)
    
    # Inicia servidor Flask
    app.run(
        host='0.0.0.0', 
        port=8080, 
        debug=False,
        threaded=True
    )
