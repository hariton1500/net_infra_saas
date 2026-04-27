# Android Screenshot Shot List

This plan is built around the actual screens that already exist in the app.

## General Rules

- Use portrait phone screenshots first
- Capture from a release-like build with realistic data
- Show real infrastructure records, not empty states where possible
- Keep each screenshot focused on one clear value

## Shot 1. Sign In

### Screen

- [auth_page.dart](../lib/src/screens/auth_page.dart)

### What to show

- sign-in tab
- clean branded left panel
- email and password form

### Store message

- Secure workspace access for your infrastructure team

### Capture note

- Use realistic corporate email
- Avoid error states

## Shot 2. Main Workspace

### Screen

- [start.dart](../lib/src/screens/start.dart)

### What to show

- hero card
- company workspace overview
- quick access to infrastructure sections

### Store message

- One workspace for routes, cabinets, tasks, and team operations

### Capture note

- Use populated metrics and active company context

## Shot 3. Infrastructure Map

### Screen

- [infrastructure_map_page.dart](../lib/src/screens/infrastructure_map_page.dart)

### What to show

- map with visible infrastructure objects
- route overlays
- selected infrastructure context

### Store message

- Keep infrastructure visibility on one shared map

### Capture note

- Prefer a meaningful area with several visible objects and one highlighted route

## Shot 4. Active Task Context

### Screen

- [start.dart](../lib/src/screens/start.dart)

### What to show

- active task card or task list
- visible current task
- task-linked workflow context

### Store message

- Connect field work to real operational tasks

### Capture note

- Use a task with a clear name and visible assignees or status

## Shot 5. Muff Notebook

### Screen

- [muff_notebook.dart](../lib/src/screens/muff_notebook.dart)

### What to show

- list or detail view of a muff
- cables, splitters, or connections
- active task badge if available

### Store message

- Document field nodes, cables, and splice logic with clarity

### Capture note

- Prefer a filled record with useful technical details

## Shot 6. Network Cabinets

### Screen

- [network_cabinet.dart](../lib/src/screens/network_cabinet.dart)

### What to show

- cabinet overview or detail screen
- equipment and ports
- task filter or map/list mode if useful

### Store message

- Keep cabinet data structured and accessible for the whole team

### Capture note

- Show a cabinet with real equipment names or port information

## Shot 7. Cable Routes

### Screen

- [cable_lines_page.dart](../lib/src/screens/cable_lines_page.dart)

### What to show

- route list or route editor
- route anchors or points
- route creation/edit context

### Store message

- Track route history and infrastructure changes in one flow

### Capture note

- Show an existing route with a clear name and geometry

## Shot 8. Employee Profile or Team Context

### Screen

- [profile_page.dart](../lib/src/screens/profile_page.dart)

### Optional alternative

- team section inside [start.dart](../lib/src/screens/start.dart)

### What to show

- employee profile with role and position
- or team/invite context from the main workspace

### Store message

- Give office and field teams shared visibility and accountability

### Capture note

- Use this as the people-and-operations closing screenshot

## Recommended Final Order

1. Sign In
2. Main Workspace
3. Infrastructure Map
4. Active Task Context
5. Muff Notebook
6. Network Cabinets
7. Cable Routes
8. Team or Profile Context

