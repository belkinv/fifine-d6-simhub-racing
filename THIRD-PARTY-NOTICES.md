# Сторонние компоненты

Этот репозиторий содержит адаптированные двоичные компоненты сторонних проектов. Авторские права на них принадлежат их авторам.

## StreamDeckSimHub

- Проект: [pre-martin/StreamDeckSimHubPlugin](https://github.com/pre-martin/StreamDeckSimHubPlugin)
- Используемый релиз: 2.3.36
- Лицензия: [GNU Lesser General Public License v3.0](COPYING.LESSER), основной текст GPL находится в [COPYING](COPYING)

## SimHub Property Server

- Проект: [pre-martin/SimHubPropertyServer](https://github.com/pre-martin/SimHubPropertyServer)
- Используемый релиз: 1.16.13
- Изменение: вызовы отправки одному TCP-клиенту сериализованы с помощью `SemaphoreSlim`, чтобы исключить одновременное использование `StreamWriter`.
- Соответствующий исходный код изменённой сборки: [Source/SimHubPropertyServer-1.16.13-d6-fix.zip](Source/SimHubPropertyServer-1.16.13-d6-fix.zip)
- Лицензия: [GNU Lesser General Public License v3.0](COPYING.LESSER), основной текст GPL находится в [COPYING](COPYING)

## SimHub

SimHub в репозитории не распространяется. Пользователь устанавливает его самостоятельно с [официального сайта](https://www.simhubdash.com/).
