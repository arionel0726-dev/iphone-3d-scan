# StoreScan — iOS RoomPlan-сканер для 2-3d-store

Простое SwiftUI-приложение: менеджер входит под существующим аккаунтом,
выбирает магазин (и, опционально, планировку), сканирует одно помещение
через RoomPlan и отправляет результат в существующий API `2-3d-store`
(`POST /api/scans`). Дальнейшая проверка и применение скана происходят в
веб-приложении (`/scans/:id`, добавлено на этапе C).

Вне MVP (сознательно не реализовано): выгрузка USDZ, сканирование
нескольких помещений за раз, работа с фотографиями, отдельная система
авторизации.

## Структура

```
StoreScan.xcodeproj/        — проект Xcode (см. ограничения ниже)
StoreScan/
  StoreScanApp.swift        — точка входа
  AppState.swift            — состояние экрана/сессии
  Models/
    ScanUploadDTO.swift      — DTO, 1:1 с back/src/scan-dto.ts
    APIModels.swift           — Store/Layout/Auth-модели
  Networking/
    APIClient.swift           — запросы к существующему API
    APIError.swift             — состояния ошибок (сеть/401/сервер)
    KeychainTokenStore.swift   — bearer-токен в Keychain
  Scanning/
    CapturedRoomDTOMapper.swift — CapturedRoom → DTO, без геометрии
    ScanCaptureCoordinator.swift — делегаты RoomPlan, состояние скана
    RoomCaptureRepresentable.swift — UIViewRepresentable для RoomCaptureView
    CameraPermission.swift      — проверка/запрос доступа к камере
    DeviceInfo.swift             — модель устройства для DTO.device
  Views/
    LoginView.swift, StorePickerView.swift, ScanCaptureView.swift,
    UploadResultView.swift, RootView.swift
  Info.plist, Assets.xcassets
StoreScanTests/
  ScanUploadDTOCodingTests.swift — тесты сериализации DTO
```

## Контракт с backend (ветка `claude/roomplan-scan-import`, 2-3d-store)

Изучены перед реализацией: `back/src/scan-dto.ts`, `back/src/scan-normalize.ts`,
`POST /api/scans`, `back/src/auth.ts` (Better Auth + bearer-плагин).
**Контракт не менялся.**

- Авторизация: `POST /api/auth/sign-in/email` (email+пароль, без
  самостоятельной регистрации — пароль выдаётся администратором через
  `bun run auth:create-user` в `back`). Ответ содержит `token` — тот же
  bearer-токен, что тестирует `auth.test.ts` веб-репозитория. Токен
  хранится в Keychain (`KeychainTokenStore`), добавляется как
  `Authorization: Bearer <token>` во все запросы. Отдельной системы
  авторизации нет.
- Список магазинов и планировок: `GET /api/stores` уже возвращает
  `layouts: LayoutSummary[]` вложенно в каждый магазин — отдельный
  endpoint для планировок не понадобился, ничего не придумывал.
- Скан: `POST /api/scans`, тело — `ScanUploadDTO` (версия 1).

### Найденная проблема контракта и её решение

`back/src/scan-dto.ts` объявляет `polygonCorners` через
`.nullable()` (не `.optional()`) — это значит, что ключ **обязателен**,
а значением может быть `null` либо массив из ≥3 точек; **отсутствующий
ключ сервер отклоняет** (`undefined` не проходит `.nullable()`).
Собственный тип RoomPlan `CapturedRoom.Surface.polygonCorners` при этом —
обычный **не-Optional** `[simd_float3]` (может быть пустым, но никогда
`nil`), что подтверждено официальной документацией Apple
(`developer.apple.com/documentation/roomplan/capturedroom/surface`).

Если бы `ScanSurfaceDTO.polygonCorners: [ScanPointDTO]?` кодировался
через обычный синтезированный `Encodable` (`encodeIfPresent`), Swift
**пропустил бы ключ целиком** для `nil` — и backend отклонял бы такой
скан с 400 для каждой поверхности без полигона. Я воспроизвёл это и
убедился, что оно реально ломает валидацию, прогнав оба варианта через
настоящую Zod-схему бэкенда (`bun run` + `scanUploadDtoSchema.safeParse`,
не только предположение) — отсутствующий ключ отклоняется, явный `null`
принимается.

**Решение — только на стороне iOS**, без изменения контракта:
`ScanSurfaceDTO` реализует `Codable` вручную (не полагаясь на
автогенерацию) и всегда кодирует `polygonCorners` явно — `null` или
массив, но никогда не пропускает ключ. См. комментарии в
`Models/ScanUploadDTO.swift`. Backend не тронут; этого было достаточно.

*Если отдельно всё же нужно "затвердить" защиту со стороны сервера*,
предложение для согласования с владельцем `2-3d-store` (не применено
здесь): ослабить `back/src/scan-dto.ts` до
`polygonCorners: z.array(scanPointSchema).min(3).max(64).nullish()`
(`nullish` = `nullable().optional()`) — это приняло бы и пропущенный
ключ, и `null`, не ломая уже написанные тесты и фикстуры из этапа A,
которые всегда передают явный `null`.

### Соответствие полей RoomPlan → DTO

| RoomPlan (`CapturedRoom`) | DTO |
|---|---|
| `.floors / .walls / .doors / .windows / .openings: [Surface]` | `surfaces[].kind` (по исходному массиву) |
| `Surface.identifier` / `Object.identifier` | `sourceId` (`.uuidString`) |
| `Surface/Object.confidence: Confidence` (`.low/.medium/.high`) | `confidence` |
| `Surface/Object.transform: simd_float4x4` | `transform`: 16 чисел, **column-major**, явное уплощение `columns.0...3` — без полагания на дефолтный `Codable` `simd_float4x4` |
| `Surface/Object.dimensions: simd_float3` | `dimensions.width/height/length` = `.x/.y/.z` — это соглашение контракта, не поля simd |
| `Surface.polygonCorners: [simd_float3]` | `polygonCorners`: `nil`, если < 3 точек, иначе массив |
| `Object.category: CapturedRoom.Object.Category` (16 случаев, см. Apple docs) | `category` + `.unknown` для `@unknown default` (enum не `frozen`, Apple может добавить случаи) |

Все преобразования координат (метры → см, повороты, система координат)
происходят **только на backend**, в `scan-normalize.ts` — на iOS
геометрии нет вообще, как и требовалось.

## Проверки, которые реально выполнены

Это sandboxed Linux-окружение **без Xcode, без Swift-тулчейна и без iOS
устройства** — `swift`/`xcodebuild` недоступны, `download.swift.org`
заблокирован прокси сессии. Поэтому сделано то, что можно было сделать
честно и проверяемо:

1. **Структурная валидация `project.pbxproj`** — не просто "похоже на
   правильный текст". Файл сгенерирован скриптом (уникальные ID, без
   опечаток) и затем разобран независимым OpenStep-парсером
   (`mod-pbxproj`/`openstep_parser`, PyPI) с проверками: нет "битых"
   ссылок на несуществующие object id; каждый `.swift`-файл на диске
   входит ровно в одну Sources-фазу нужного таргета (17 файлов в
   `StoreScan`, 1 — в `StoreScanTests`); `StoreScanTests` зависит от
   `StoreScan` через `PBXTargetDependency`/`PBXContainerItemProxy`;
   `RoomPlan.framework`/`AVFoundation.framework` подключены к таргету
   приложения, `XCTest.framework` — к тестовому. Это ловит типичные
   причины "Xcode не может открыть проект", но **не равно** реальному
   `xcodebuild build` — его я не запускал и не заявляю, что он прошёл.
2. **Кросс-проверка формы DTO против настоящей Zod-схемы backend.**
   Собрал литеральный JSON, который выдаёт Swift-кодировщик (включая
   оба варианта `polygonCorners` — `null` и массив — и оба варианта
   опциональных `device.osVersion/roomPlanVersion`), и пропустил его
   через `scanUploadDtoSchema.safeParse` из `back/src/scan-dto.ts` на
   Bun — все случаи прошли, а вариант с пропущенным ключом
   `polygonCorners` (то, что дал бы дефолтный `Codable`) корректно
   отклонён. Это не замена `swift test`, но подтверждает, что именно
   эта форма JSON принимается настоящим бэкендом, а не предположением о
   нём.
3. **API RoomPlan сверен с официальной документацией Apple** (fetch
   `developer.apple.com/documentation/roomplan/...`) прямо во время
   работы — не по памяти: точные сигнатуры `CapturedRoom`,
   `CapturedRoom.Surface`/`.Object`, `Category`-перечисления (16 случаев
   объектов, 5 — поверхностей), `Confidence`, `RoomCaptureSession`
   (`isSupported`, `CaptureError` без варианта "нет доступа к камере" —
   поэтому разрешение камеры проверяется отдельно через AVFoundation),
   `RoomCaptureView`/`RoomCaptureViewDelegate`/`RoomCaptureSessionDelegate`.

### Осталось непроверенным (ограничения)

- **`swift build` / `xcodebuild` не запускались.** Возможны ошибки
  компиляции, которые ловит только реальный компилятор Swift (опечатка
  в имени типа, несовпадение сигнатуры делегата и т.п.) — несмотря на
  вычитку и сверку с документацией, гарантии "компилируется" нет.
- **Проект не открывался в настоящем Xcode.** Структурная валидация
  парсером исключает большинство причин "повреждённого проекта", но не
  заменяет открытие в Xcode. **Запасной путь**, если `.xcodeproj` всё же
  не открывается: создать новый проект (File → New → Project → iOS App,
  SwiftUI, Swift) с именем `StoreScan`, удалить сгенерированные
  `ContentView.swift`/`Item.swift`, перетащить в него содержимое папок
  `StoreScan/` и `StoreScanTests/` из этого репозитория («Create groups»,
  добавить тестовый таргет через File → New → Target → Unit Testing
  Bundle) — исходники самодостаточны и не зависят от конкретной сборки
  `.pbxproj`.
- **Ни один реальный скан RoomPlan не выполнялся** — устройства с LiDAR
  в этом окружении нет. Преобразование `CapturedRoom → DTO` вычитано и
  сверено с документацией Apple, но **не проверено на реальных
  размерах/ориентации стен помещения**. В частности:
  - точный байтовый формат `transform` (column-major, 16 чисел) — это
    контракт, который задаёт сам backend (см. `scan-dto.ts`), и он
    реализован явным уплощением `simd_float4x4.columns`, а не через
    штатный `Codable` — но то, что RoomPlan на реальном сканировании
    действительно даёт геометрически вменяемые матрицы в этой
    раскладке, подтверждается только документацией Apple, не измерением
    на устройстве;
  - связка "какая локальная ось стены — направление длины, какая —
    толщина" (используется backend'ом в `scan-normalize.ts` как fallback
    при отсутствии `polygonCorners`) помечена там же как неподтверждённое
    устройством предположение — это не изменилось;
  - код делегата `RoomCaptureViewDelegate`/`RoomCaptureSessionDelegate`
    (`ScanCaptureCoordinator.swift`) написан по документированным
    сигнатурам методов, но реальный пример кода Apple (sample project) не
    был доступен для сверки построчно — только описание API.
  
  **Пока нет возможности сканировать на реальном устройстве, результат
  преобразования координат проверенным не считается** — это сознательно
  не заявляется как сделанное.
- Тестовый таргет не запускался (`swift test`/`xcodebuild test`) —
  только написан и прогнан "на бумаге" плюс кросс-проверен сформированный
  JSON против реальной Zod-схемы (см. выше).
- Иконка приложения (`AppIcon.appiconset`) без растровых изображений —
  это предупреждение сборки, не ошибка; требуется реальная иконка перед
  публикацией.

## Демо-скан (Debug-only, без LiDAR)

У тестирующего нет устройства с LiDAR, поэтому добавлен отдельный путь,
который проверяет именно интеграцию с API (авторизация + `POST /api/scans`
+ валидация на сервере), а не само RoomPlan-сканирование:

- На экране сканирования (`ScanCaptureView.swift`) в состоянии "Готово к
  сканированию" и на экране "Устройство не поддерживается" появляется
  кнопка **"Демо-скан (тестовые данные)"** — целиком обёрнута в
  `#if DEBUG`, поэтому физически отсутствует в Release-сборке
  (`DemoScanFixture.swift` целиком под тем же `#if DEBUG`).
- Кнопка строит фиксированный `ScanUploadDTO` (`DemoScanFixture.swift`) —
  маленькая прямоугольная комната 4×3 м, пол с `polygonCorners`, 4 стены,
  дверь, окно и один объект — строго по форме `back/src/scan-dto.ts`, и
  отправляет его через **тот же самый** `APIClient.uploadScan`, что и
  настоящий скан: тот же bearer-токен, тот же эндпоинт, та же обработка
  409/401/ошибок сети. `RoomCaptureCoordinator`/`CapturedRoomDTOMapper` при
  этом не используются и не изменены.
- Это явно показано как тестовые данные, а не реальный скан:
  - `device.model = "Demo Fixture (без LiDAR)"` и
    `device.roomPlanVersion = "demo-fixture-v1"` — свободные текстовые поля,
    которые контракт и так разрешает, никакого нового поля в DTO не
    добавлено;
  - после отправки экран результата (`UploadResultView.swift`) показывает
    отдельный жёлтый бейдж "ДЕМО-ДАННЫЕ" и другой текст, явно говорящий,
    что это не реальное сканирование.
- Проверено (без Xcode): собрал тот же JSON, который выдаёт
  `DemoScanFixture.makeUploadDTO`, вручную (поле за полем, включая
  `polygonCorners: null` для стен/двери/окна и массив из 4 точек для пола)
  и пропустил через настоящую `scanUploadDtoSchema.safeParse` из
  `back/src/scan-dto.ts` на Bun — принято без ошибок.
- Добавлены Swift-тесты в `ScanUploadDTOCodingTests.swift`
  (`testDemoScanFixture...`): форма верхнего уровня, `polygonCorners` у
  пола ≥ 3 точек, `targetLayoutId: nil` кодируется как явный JSON `null`
  (не отсутствующий ключ), round-trip через `Codable`, и явная метка
  "demo" в `device.model`.
- Как и везде в этом репозитории: `swift test`/`xcodebuild` здесь не
  запускались (нет Swift-тулчейна в этом окружении) — тесты написаны и
  логически сверены с реальной Zod-схемой, но не прогнаны настоящим
  компилятором. Структурная валидация `project.pbxproj` после добавления
  `DemoScanFixture.swift` пройдена (см. выше).

## Настройка для локальной разработки

1. `back` и `front` из `2-3d-store` должны быть подняты (см. их README).
2. `StoreScan/Info.plist` уже содержит `APIBaseURL`/`WebAppBaseURL`
   (`http://localhost:3001`/`http://localhost:3000`) и ATS-исключение
   для `localhost` — **только для разработки**. На реальном устройстве
   (не симуляторе) замените на LAN IP Mac (`http://192.168.x.x:3001`)
   или на настоящий HTTPS backend и уберите исключение ATS.
3. Создайте менеджера через `back`: `AUTH_EMAIL=... AUTH_PASSWORD=...
   bun run auth:create-user` — тот же аккаунт работает и в iOS
   приложении, и в веб-редакторе.
4. Соберите на реальном устройстве с LiDAR (iPhone 12 Pro+/iPad Pro
   2020+) — RoomPlan не работает в симуляторе.

## Минимальная цель деплоя

`IPHONEOS_DEPLOYMENT_TARGET = 17.0`. RoomPlan формально доступен с iOS
16.0 (по документации Apple), но в сообществе разработчиков
(developer.apple.com/forums) отмечалось, что качество `floors`/
`polygonCorners` улучшилось к iOS 17 — а устройства с LiDAR и так не
новее iPhone 12 Pro (2020), так что iOS 17 как минимум не сужает
практическую аудиторию.
