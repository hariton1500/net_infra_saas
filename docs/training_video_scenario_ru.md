# Сценарий обучающего ролика Net Infra SaaS

Цель: показать текущие возможности продукта на реалистичных ситуациях небольшой телеком-компании: запуск рабочего пространства, постановка задачи, выезд бригады, создание/редактирование объектов сети, работа с картой, муфтами, шкафами, кабельными линиями, командой и синхронизацией.

Рекомендуемый формат:

- Полная версия: 18-25 минут.
- Короткие главы: 6-9 отдельных роликов по 2-4 минуты.
- Язык записи: русский или английский. Для международных лидов можно оставить интерфейс на английском, а озвучку делать на русском для внутренней подготовки.
- Демоданные: использовать вымышленную компанию и демо-зону. Если показывается зона Perrenjas для Interfiber, отдельно сказать, что это учебный пример, а не реальная схема сети клиента.

## Перед записью

Подготовить демо-аккаунт:

- Сайт: `https://netinfra.pro`
- Email: `demo.owner@netinfra.local`
- Пароль: `DemoNetInfra2026!`

Подготовить демо-компанию:

- Название: `Demo Fiber Operations`
- Роли сотрудников: владелец, инженер, монтажник, диспетчер.
- Задачи:
  - `FTTH build - Perrenjas North`
  - `Customer outage - cabinet PRJ-CAB-02`
  - `As-built verification - Qukes route`

Подготовить демо-объекты:

- 2-3 сетевых шкафа.
- 3-5 муфт или PON-боксов.
- 2 кабельные трассы.
- Кабели с разным числом волокон.
- Несколько соединений между волокнами, splitter-портами и портами коммутатора.

## Структура ролика

### 0. Открытие

Длительность: 40-60 секунд.

Цель сцены: объяснить, для кого продукт и какую работу сейчас покажем.

На экране:

1. Открыть `https://netinfra.pro`.
2. Показать экран входа.
3. Коротко показать название продукта.

Текст диктора:

> В этом видео покажем Net Infra SaaS на примере небольшой компании, которая строит и обслуживает оптическую сеть. Пройдем типичный рабочий день: руководитель создает задачу, инженер добавляет объекты на карту, бригада фиксирует муфты и шкафы, а затем команда проверяет и закрывает работу.
>
> Сценарий учебный. Данные на карте используются только для демонстрации процесса.

Voice-over English:

> In this video, we will show Net Infra SaaS using the example of a small company that builds and maintains a fiber network. We will go through a typical working day: a manager creates a task, an engineer adds objects on the map, the field team documents closures and cabinets, and then the team verifies and closes the work.
>
> This is a training scenario. The data shown on the map is used only to demonstrate the workflow.

Жизненная ситуация:

> Компания ведет сеть в Excel, мессенджерах и отдельных картах. Нужно собрать рабочий процесс в одном месте, чтобы не терять изменения после выездов.

Real-life situation English:

> The company manages its network through Excel files, messengers, and separate maps. The goal is to bring the workflow into one place so field changes are not lost after site visits.

### 1. Вход, компания и рабочее пространство

Длительность: 2-3 минуты.

Цель сцены: показать базовый старт и multi-company контекст.

На экране:

1. Войти в демо-аккаунт.
2. Показать главное рабочее пространство компании.
3. Открыть профиль.
4. Показать имя пользователя, компанию, роль, должность, slug.
5. Вернуться на главный экран.

Текст диктора:

> После входа пользователь попадает в рабочее пространство своей компании. Данные компании изолированы: задачи, сотрудники, шкафы, муфты и маршруты относятся к конкретной организации.
>
> В профиле видно, кто сейчас работает в системе, к какой компании он относится, какая у него роль и должность. Это важно для командной работы: в инфраструктурных задачах нужно понимать не только что изменилось, но и кто отвечает за изменение.

Voice-over English:

> After signing in, the user enters the workspace of their company. Company data is separated: tasks, employees, cabinets, closures, and routes belong to a specific organization.
>
> In the profile, we can see who is currently using the system, which company they belong to, and what their role and position are. This matters for team operations, because infrastructure work needs clear responsibility, not just a record of what changed.

Жизненная ситуация:

> Новый инженер подключается к системе. Ему не нужно искать актуальные Excel-файлы и схемы в чатах: после входа он видит рабочее пространство компании.

Real-life situation English:

> A new engineer joins the system. They do not need to search for the latest Excel files or diagrams in chats. After signing in, they see the company workspace.

Что подчеркнуть:

- Вход по email/password.
- Рабочее пространство компании.
- Профиль пользователя.
- Роль и должность.

### 2. Команда и приглашение сотрудников

Длительность: 2-3 минуты.

Цель сцены: показать работу компании, а не одного пользователя.

На экране:

1. Открыть раздел `Company team`.
2. Показать список сотрудников.
3. Показать блок `Pending invites`.
4. Создать приглашение сотруднику:
   - email;
   - роль `Employee` или `Administrator`;
   - должность, если доступно.
5. Показать код приглашения в списке pending invites.

Текст диктора:

> Net Infra SaaS рассчитан на команду. Владелец или администратор может смотреть сотрудников, видеть ожидающие приглашения и подключать новых людей.
>
> Например, компания нанимает монтажника для работ по новому FTTH-району. Руководитель создает приглашение, выбирает роль и должность. После подключения сотрудник будет работать в том же пространстве и видеть свои задачи.

Voice-over English:

> Net Infra SaaS is designed for a team, not just for one user. The owner or administrator can review employees, see pending invitations, and invite new people.
>
> For example, the company brings in a technician for work in a new FTTH area. The manager creates an invitation, selects the role and position, and after the employee joins, they work in the same company workspace and can see their assigned tasks.

Жизненная ситуация:

> Подрядчик подключает временную бригаду на строительство участка. Нужно дать доступ к задачам и объектам, но сохранить контроль через роли.

Real-life situation English:

> A contractor brings in a temporary crew for a construction segment. The company needs to give access to tasks and objects while keeping control through roles.

Что подчеркнуть:

- Список сотрудников.
- Pending invites.
- Роли: employee/admin.
- Должности.
- Командная ответственность.

### 3. Задачи как рабочий контекст

Длительность: 3-4 минуты.

Цель сцены: показать, что новые объекты и изменения привязываются к активной задаче.

На экране:

1. На главном экране показать список задач.
2. Создать новую задачу:
   - `FTTH build - Perrenjas North`;
   - описание: `Build and document new fiber segment with closures, route, cabinet links.`
3. Открыть детали задачи.
4. Назначить сотрудников.
5. Активировать задачу.
6. Показать баннер активной задачи.
7. Показать фильтры `All` и `Mine`, если есть.

Текст диктора:

> Задача в Net Infra SaaS - это рабочий контекст для полевых изменений. Перед тем как добавлять маршруты, шкафы или муфты, инженер активирует задачу. После этого новые объекты и изменения связываются с этой задачей.
>
> Это помогает восстановить историю: что было сделано, кем, в рамках какого выезда или проекта.

Voice-over English:

> In Net Infra SaaS, a task is the working context for field changes. Before adding routes, cabinets, or closures, the engineer activates a task. After that, new objects and changes are linked to this task.
>
> This helps the company reconstruct the history of work: what was done, who did it, and which visit or project it belonged to.

Жизненная ситуация:

> Оператор строит новый участок FTTH. Если бригада просто добавит точки на карту без контекста, через месяц будет сложно понять, к какому проекту относились изменения. Активная задача решает эту проблему.

Real-life situation English:

> An operator is building a new FTTH segment. If the crew only adds points on the map without context, it will be difficult a month later to understand which project those changes belonged to. The active task solves this problem.

Показать завершение задачи позже:

- Назначить сотрудников.
- `Mark completed`.
- `Mark verified`.
- `Send to archive`.

### 4. Карта инфраструктуры: маршруты, объекты и фильтры

Длительность: 4-5 минут.

Цель сцены: показать карту как основу общей картины сети.

На экране:

1. Открыть `Infrastructure map`.
2. Показать баннер активной задачи.
3. Переключить map layer.
4. Создать кабельный маршрут:
   - нажать кнопку маршрута;
   - выбрать стартовую точку;
   - добавить промежуточные точки;
   - выбрать конечную точку;
   - подтвердить название и параметры.
5. Выбрать маршрут.
6. Отредактировать маршрут:
   - нажать edit;
   - передвинуть промежуточную точку;
   - завершить редактирование.
7. Установить муфту на маршруте:
   - выбрать маршрут;
   - нажать split;
   - выбрать место на трассе;
   - подтвердить данные муфты.
8. Показать фильтр по задаче: все объекты / только объекты активной задачи.

Текст диктора:

> Карта показывает инфраструктуру в географическом контексте. Здесь можно создавать кабельные маршруты, редактировать их, устанавливать муфты или PON-боксы на трассе и проверять объекты.
>
> Когда активна задача, новые изменения на карте связываются с ней. Фильтр по задачам позволяет руководителю быстро отделить общий слой сети от изменений конкретного проекта.

Voice-over English:

> The infrastructure map shows the network in its geographic context. Here we can create cable routes, edit them, install closures or PON boxes on a route, and inspect network objects.
>
> When a task is active, new map changes are linked to that task. The task filter helps a manager separate the general network layer from the changes made for a specific project.

Жизненная ситуация 1:

> Проектировщик подготовил трассу, но на местности бригада обошла препятствие. Инженер редактирует промежуточные точки маршрута, и команда видит актуальную линию.

Real-life situation English 1:

> The designer prepared a route, but in the field the crew had to bypass an obstacle. The engineer edits the intermediate route points, and the team sees the updated line.

Жизненная ситуация 2:

> Во время строительства обнаружено место, где нужна муфта. Инженер выбирает маршрут, ставит муфту на трассу и связывает ее с текущей задачей.

Real-life situation English 2:

> During construction, the team finds a location where a closure is needed. The engineer selects the route, installs the closure on the line, and links it to the current task.

Что подчеркнуть:

- Создание маршрута.
- Редактирование маршрута.
- Установка муфты на route.
- Осмотр объектов.
- Слои карты.
- Фильтр по задачам.
- Удаление маршрута через подтверждение, если нужно показать.

### 5. Журнал муфт и PON-боксы

Длительность: 4-5 минут.

Цель сцены: показать детальную документацию муфты и волокон.

На экране:

1. Открыть `Closure notebook`.
2. Переключить список/карту.
3. Создать новую муфту:
   - имя;
   - район;
   - адрес;
   - комментарий;
   - точка на карте;
   - флаг `This is a PON box`, если подходит.
4. Открыть муфту в деталях.
5. Добавить кабель:
   - fiber count;
   - side left/right;
   - color scheme;
   - label.
6. Добавить второй кабель.
7. Добавить splitter:
   - ratio;
   - side;
   - orientation.
8. Добавить соединение:
   - drag fiber to fiber/splitter port;
   - или через `Add` в Connections.
9. Добавить комментарий к волокну.
10. Показать `Get signal from port` / `Build plan`, если подготовлены данные.
11. Показать кнопку sync: красная - есть несинхронизированные изменения, зеленая - чисто.

Текст диктора:

> Журнал муфт нужен для технической памяти сети. Внутри муфты можно вести кабели, волокна, splitters, соединения и комментарии по отдельным волокнам.
>
> Например, бригада приехала на объект, добавила новый отвод и подключила splitter. После выезда эти изменения остаются не в чате и не в фотографии, а в структурированной записи муфты.

Voice-over English:

> The closure notebook is used to preserve the technical memory of the network. Inside a closure, the team can document cables, fibers, splitters, connections, and comments for individual fibers.
>
> For example, a field crew visits a site, adds a new branch, and connects a splitter. After the visit, these changes are not lost in a chat message or a photo. They remain as a structured closure record.

Жизненная ситуация 1:

> Монтажник вскрыл муфту после аварии и обнаружил, что одно волокно было переподключено. Он добавляет комментарий к волокну и обновляет соединение.

Real-life situation English 1:

> A technician opens a closure after an outage and discovers that one fiber has been reconnected. They add a comment to the fiber and update the connection.

Жизненная ситуация 2:

> В PON-боксе добавили splitter 1:8 для новых абонентов. Инженер фиксирует splitter и связи, чтобы потом можно было понять путь сигнала.

Real-life situation English 2:

> A 1:8 splitter is added in a PON box for new subscribers. The engineer records the splitter and its connections so the signal path can be understood later.

Что подчеркнуть:

- Муфта и PON-бокс.
- Список и карта.
- Кабели и волокна.
- Splitters.
- Connections.
- Комментарии к волокнам.
- Синхронизация и refresh.

### 6. Сетевые шкафы: оборудование, порты и соединения

Длительность: 4-5 минут.

Цель сцены: показать структурированный учет шкафов, портов, кабелей и связей.

На экране:

1. Открыть `Network cabinets`.
2. Переключить список/карту.
3. Создать шкаф:
   - имя;
   - адрес/место;
   - комментарий;
   - точка на карте.
4. Открыть шкаф.
5. Добавить switch:
   - port count;
   - port type.
6. Открыть меню порта:
   - комментарий;
   - тип;
   - splitter data, если доступно;
   - trace port on infrastructure map.
7. Добавить кабель с волокнами.
8. Соединить fiber endpoint с switch port:
   - drag endpoint;
   - или ручной выбор в Connections.
9. Показать линии соединений на схеме шкафа.
10. Нажать `Trace` для порта и показать переход на карту с подсветкой пути, если демоданные подготовлены.

Текст диктора:

> Сетевой шкаф - это место, где особенно легко потерять актуальное состояние. В Net Infra SaaS шкаф хранит оборудование, порты, кабели, волокна, соединения и комментарии.
>
> Когда инженер меняет порт или подключение, он фиксирует это прямо в карточке шкафа. Позже другой сотрудник может открыть тот же шкаф и увидеть не только список оборудования, но и связи между портами и кабелями.

Voice-over English:

> A network cabinet is one of the places where it is very easy to lose the current state. In Net Infra SaaS, a cabinet keeps equipment, ports, cables, fibers, connections, and comments in one structured view.
>
> When an engineer changes a port or a connection, the change is recorded directly in the cabinet. Later, another team member can open the same cabinet and see not only the equipment list, but also the relationships between ports and cables.

Жизненная ситуация 1:

> Клиент сообщает о проблеме. Диспетчер знает шкаф и порт. Инженер открывает шкаф, смотрит связь порта с кабелем и запускает трассировку на карте.

Real-life situation English 1:

> A customer reports a problem. The dispatcher knows the cabinet and port. The engineer opens the cabinet, checks the connection between the port and the cable, and starts tracing it on the map.

Жизненная ситуация 2:

> При подключении нового дома монтажник добавляет кабель, соединяет волокно с портом и оставляет комментарий. Руководитель видит, что изменение связано с активной задачей.

Real-life situation English 2:

> When connecting a new building, the technician adds a cable, connects a fiber to a port, and leaves a comment. The manager can see that the change is linked to the active task.

Что подчеркнуть:

- Шкафы на карте.
- Switches and ports.
- Cables and fibers.
- Connections.
- Port comments/types/splitter data.
- Trace to infrastructure map.
- Sync/refresh.

### 7. Кабельные линии как отдельный рабочий раздел

Длительность: 2-3 минуты.

Цель сцены: показать, что кабельные маршруты можно вести и в отдельном разделе, не только через общую карту.

На экране:

1. Открыть `Cable lines`.
2. Показать список маршрутов.
3. Создать `New route`.
4. Выбрать точки на карте.
5. Привязать start/end к объектам, если доступны:
   - cabinet;
   - closure;
   - unlinked.
6. Сохранить.
7. Выбрать маршрут, показать детали.
8. Отредактировать или удалить через подтверждение.
9. Нажать sync/refresh.

Текст диктора:

> Раздел кабельных линий помогает работать именно с маршрутами: создавать, выбирать, редактировать и привязывать их к объектам сети. Это удобно, когда задача дня - не вся инфраструктура сразу, а трассы между точками.

Voice-over English:

> The cable lines section is focused specifically on routes. It helps create, select, edit, and bind routes to network objects. This is useful when the work of the day is not the whole infrastructure layer, but the cable paths between specific points.

Жизненная ситуация:

> Компания переносит часть сети на новую опору или прокладывает резервную линию между шкафом и муфтой. Инженер создает маршрут, привязывает начало и конец к объектам, а затем сохраняет его в общей базе.

Real-life situation English:

> The company moves part of the network to a new pole or builds a backup line between a cabinet and a closure. The engineer creates a route, links the start and end to network objects, and saves it in the shared database.

Что подчеркнуть:

- Отдельный список маршрутов.
- New route.
- Start/end anchors.
- Linked/unlinked endpoints.
- Sync/refresh.

### 8. Проверка, завершение и архив задачи

Длительность: 2-3 минуты.

Цель сцены: закрыть жизненный цикл работы.

На экране:

1. Вернуться на главный экран.
2. Открыть активную задачу.
3. Показать recorded additions / work log, если есть.
4. Назначить сотрудников, если не было сделано.
5. Нажать `Mark completed`.
6. Нажать `Mark verified`.
7. Нажать `Send to archive`.
8. Показать, что задача больше не активна или ушла из рабочего списка.

Текст диктора:

> После полевой работы задача проходит нормальный жизненный цикл: назначение, выполнение, проверка и архив. Это помогает отделить рабочий процесс от просто набора объектов на карте.
>
> Руководитель видит, что именно было создано или изменено в рамках задачи, кто участвовал и когда работа была завершена.

Voice-over English:

> After field work is finished, a task goes through a normal lifecycle: assignment, completion, verification, and archive. This helps separate the work process from a simple collection of objects on the map.
>
> The manager can see what was created or changed within the task, who participated, and when the work was completed.

Жизненная ситуация:

> Бригада закончила строительство участка. Инженер отмечает задачу выполненной, технический руководитель проверяет изменения, после чего задача уходит в архив.

Real-life situation English:

> The field crew finishes a construction segment. The engineer marks the task as completed, the technical manager verifies the changes, and then the task is archived.

Что подчеркнуть:

- Completed.
- Verified.
- Archive.
- Work log / recorded additions.
- Ответственность и контроль.

### 9. Сценарий аварии: от обращения клиента до проверки трассы

Длительность: 3-4 минуты.

Цель сцены: показать продукт не только для строительства, но и для эксплуатации.

На экране:

1. Создать задачу `Customer outage - cabinet PRJ-CAB-02`.
2. Активировать ее.
3. Открыть `Network cabinets`.
4. Найти шкаф.
5. Открыть switch/port.
6. Посмотреть комментарии и тип порта.
7. Запустить `Trace` на карте.
8. На карте показать маршрут/подсветку.
9. Открыть связанную муфту.
10. Внести комментарий к волокну или соединению.
11. Вернуться к задаче и отметить выполненной.

Текст диктора:

> В эксплуатации важна скорость поиска контекста. Если клиент или участок сети недоступен, инженер начинает не с догадок, а с объекта: шкаф, порт, кабель, муфта, трасса.
>
> Трассировка и связанные записи помогают понять, куда идет сигнал и какие объекты стоит проверить в первую очередь.

Voice-over English:

> In network operations, the speed of finding context matters. If a customer or part of the network is down, the engineer does not start from guesswork. They start from an object: a cabinet, port, cable, closure, or route.
>
> Signal tracing and related records help the team understand where the signal path goes and which objects should be checked first.

Жизненная ситуация:

> У нескольких клиентов в районе пропал интернет. Диспетчер создает аварийную задачу, инженер проверяет шкаф, трассирует порт, открывает связанную муфту и фиксирует результат проверки.

Real-life situation English:

> Several customers in the area lose internet access. The dispatcher creates an outage task, the engineer checks the cabinet, traces the port, opens the related closure, and records the inspection result.

Что подчеркнуть:

- Задача аварии.
- Поиск шкафа.
- Port trace.
- Переход к карте.
- Проверка муфты.
- Комментарий как техническая память.

### 10. Сценарий строительства: от трассы до as-built проверки

Длительность: 3-4 минуты.

Цель сцены: показать end-to-end workflow для подрядчика или ISP.

На экране:

1. Создать задачу `As-built verification - Qukes route`.
2. Активировать.
3. Открыть карту и создать/проверить маршрут.
4. Установить муфту на маршруте.
5. Открыть муфту в журнале.
6. Добавить кабели и splitter.
7. Открыть шкаф и добавить подключение.
8. Вернуться к задаче, проверить additions.
9. Mark completed / verified.

Текст диктора:

> Для строительства FTTH важно не просто нарисовать трассу, а довести работу до проверенной документации. В этом сценарии маршрут, муфта, кабели, splitter, шкаф и задача связаны в одну историю.
>
> Так команда получает не отдельные заметки, а рабочий as-built процесс: что планировали, что изменили в поле и что в итоге принято.

Voice-over English:

> For FTTH construction, it is not enough to simply draw a route. The team needs to bring the work to verified documentation. In this scenario, the route, closure, cables, splitter, cabinet, and task become one connected work history.
>
> This gives the company a practical as-built workflow: what was planned, what changed in the field, and what was finally accepted.

Жизненная ситуация:

> Подрядчик завершает участок и должен передать оператору понятную картину: где идет линия, какие муфты стоят, какие кабели заведены, какие соединения выполнены.

Real-life situation English:

> A contractor completes a segment and needs to hand over a clear picture to the operator: where the line runs, which closures were installed, which cables were brought in, and which connections were made.

### 11. Синхронизация, обновление и работа с локальными изменениями

Длительность: 2 минуты.

Цель сцены: объяснить красный/зеленый cloud и refresh.

На экране:

1. В `Closure notebook` или `Network cabinets` сделать изменение.
2. Показать cloud button в красном состоянии.
3. Нажать sync.
4. Показать зеленое состояние.
5. Нажать refresh.

Текст диктора:

> В некоторых рабочих разделах изменения могут сначала появляться локально. Цветная cloud-кнопка показывает состояние синхронизации. Красный цвет означает, что есть несинхронизированные записи. Зеленый - данные сохранены.
>
> Refresh загружает актуальные записи из хранилища и помогает сверить состояние после работы других сотрудников.

Voice-over English:

> In some work sections, changes may first appear locally. The colored cloud button shows the synchronization state. Red means there are unsynced records. Green means the data is clean and saved.
>
> Refresh reloads the latest records from storage and helps the team check the current state after other employees have worked in the system.

Жизненная ситуация:

> Инженер работал на объекте, внес изменения, а затем синхронизировал их, чтобы офис увидел обновленные данные.

Real-life situation English:

> An engineer works on site, makes changes, and then synchronizes them so the office can see the updated data.

### 12. Закрытие ролика

Длительность: 40-60 секунд.

На экране:

1. Главный экран.
2. Быстро показать три раздела: карта, муфты, шкафы.
3. Показать сайт `https://netinfra.pro`.

Текст диктора:

> Мы прошли основные возможности Net Infra SaaS: задачи, команду, карту инфраструктуры, кабельные маршруты, муфты, PON-боксы, шкафы, порты, соединения, трассировку и синхронизацию.
>
> Главная идея продукта - дать небольшой телеком-компании единое рабочее пространство, где полевая работа, объекты сети и ответственность команды связаны между собой.
>
> Net Infra SaaS. Infrastructure operations, documented and coordinated.

Voice-over English:

> We have covered the main capabilities of Net Infra SaaS: tasks, team management, the infrastructure map, cable routes, closures, PON boxes, cabinets, ports, connections, signal tracing, and synchronization.
>
> The main idea of the product is to give a small telecom company one shared workspace where field work, network objects, and team responsibility are connected.
>
> Net Infra SaaS. Infrastructure operations, documented and coordinated.

## Короткая версия на 5-7 минут

Если нужен быстрый ролик для лида, сократить до таких сцен:

1. Вход и главная идея.
2. Создание задачи и активация.
3. Карта: маршрут и муфта на маршруте.
4. Муфта: кабели, splitter, connections.
5. Шкаф: switch, ports, cable, trace.
6. Закрытие задачи.
7. Сайт и предложение демо-доступа.

## Версия для Interfiber

Акцент:

- локальный ISP;
- инвентаризация сети;
- подключения клиентов;
- аварии и поддержка;
- техническая память по муфтам и шкафам.

Фраза в начале:

> В демонстрации используется учебная зона вокруг Perrenjas. Это не реальная карта сети Interfiber, а пример того, как можно вести объекты, маршруты и задачи в системе.

Сцены, которые стоит оставить:

- карта зоны;
- шкаф и порт;
- муфта/PON-бокс;
- аварийная задача;
- комментарии к волокнам;
- закрытие задачи.

## Версия для Optix Infra

Акцент:

- FTTH planning;
- field verification;
- construction tracking;
- as-built documentation;
- coordination with contractors.

Сцены, которые стоит оставить:

- создание маршрута;
- редактирование маршрута после полевого изменения;
- установка муфты на трассе;
- муфта с кабелями и splitter;
- завершение и проверка задачи.

## Чеклист качества перед отправкой лидам

- На экране нет реальных клиентских данных.
- Пароль демо-аккаунта не показывается в ролике, если видео будет публичным.
- Сайт `https://netinfra.pro` показан в начале или конце.
- Если используется регион реального лида, явно сказано, что это demo example.
- Все показанные функции реально доступны в текущем интерфейсе.
- Звук записан без шума, курсор двигается медленно, переходы между разделами не слишком быстрые.
- Видео нарезано по главам или содержит таймкоды.

## Таймкоды полной версии

| Время | Глава |
|---|---|
| 00:00 | Открытие |
| 00:50 | Вход и рабочее пространство |
| 03:00 | Команда и приглашения |
| 05:30 | Задачи и активная задача |
| 09:00 | Карта инфраструктуры |
| 14:00 | Журнал муфт и PON-боксы |
| 19:00 | Сетевые шкафы |
| 24:00 | Кабельные линии |
| 27:00 | Завершение задачи |
| 30:00 | Аварийный сценарий |
| 34:00 | Строительный/as-built сценарий |
| 38:00 | Синхронизация |
| 40:00 | Закрытие |
