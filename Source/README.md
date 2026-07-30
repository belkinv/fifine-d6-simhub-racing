# Исходный код исправленного Property Server

`SimHubPropertyServer-1.16.13-d6-fix.zip` содержит соответствующий исходный код DLL из `Payload/Installers/PropertyServer.dll`.

Основа: `pre-martin/SimHubPropertyServer`, релиз `v1.16.13`, коммит `1f06bd50606e335978c9386b7c8a18737f00140f`.

Изменение находится в `PropertyServer.Plugin/PropertyServer/Comm/Client.cs`: отправка сообщений одному клиенту защищена `SemaphoreSlim`. Блокировка освобождается до отключения клиента, чтобы не создавать взаимную блокировку.

Регрессионная проверка:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ConcurrentSend.ps1 -PropertyServerDll <путь-к-PropertyServer.dll>
```

Тест запускает два параллельных вызова `Client.SendString`. Исходная DLL отключает клиента, исправленная DLL сохраняет соединение.

Лицензия исходного проекта — LGPL-3.0-or-later. Тексты лицензий находятся также в корне этого репозитория.
