# ASCEND — Documentación de diseño

> **Crecé constantemente.**
> Plataforma de crecimiento personal: objetivos, misiones, gamificación (Aura), comunidad e IA.

## Estado del proyecto

🟢 **Roadmap completo: fases 0 a 10 cerradas.** Monorepo con 7 paquetes y **813 tests en verde** (544 de Dart · 115 de reglas · 154 de Cloud Functions), 0 issues de análisis.

🟢 **Las dos aplicaciones son reales.** El panel de administración entra con una cuenta con rol de administrador, lee datos de Firestore en vivo y registra cada acción en `auditLog`. Ver [14-FASE-8-RESULTADO.md](14-FASE-8-RESULTADO.md).

▶️ **Para ver la app funcionando hoy** no hace falta nada de eso: con los emuladores locales anda entera. Ver [18-CORRER-SIN-FIREBASE.md](18-CORRER-SIN-FIREBASE.md).

⏳ **Para ir contra Firebase real** sí: `flutterfire configure`, el despliegue de reglas y funciones, la API key de Gemini y el plan Blaze para Storage. Ver [17-INFORME-FINAL.md](17-INFORME-FINAL.md).

🟡 **BUG-001** corregido a nivel de código, pendiente de verificación contra Firebase real. Ver [06-BUGS-CONOCIDOS.md](06-BUGS-CONOCIDOS.md).

Detalle verificable en [04-FASE-0-RESULTADO.md](04-FASE-0-RESULTADO.md), [05-FASE-1-RESULTADO.md](05-FASE-1-RESULTADO.md) y [07-FASE-2A-RESULTADO.md](07-FASE-2A-RESULTADO.md).

## Documentos

| Documento | Contenido |
|-----------|-----------|
| [00-ARQUITECTURA.md](00-ARQUITECTURA.md) | Principios, stack justificado, ADRs, capas, árbol de carpetas, DI, resiliencia, design system, performance, seguridad, riesgos |
| [01-MODELO-DATOS.md](01-MODELO-DATOS.md) | Colecciones de Firestore, esquemas campo por campo, relaciones, índices, roles, reglas de seguridad, Cloud Functions |
| [02-NAVEGACION-PANTALLAS.md](02-NAVEGACION-PANTALLAS.md) | Diagramas de navegación móvil y admin, 54 + 24 pantallas, 10 grupos de funcionalidades |
| [03-ROADMAP.md](03-ROADMAP.md) | 10 fases con entregables y criterios de aceptación |
| [04-FASE-0-RESULTADO.md](04-FASE-0-RESULTADO.md) | Resultado verificado de la Fase 0: criterios cumplidos, desvíos del diseño y bloqueantes de entorno |
| [05-FASE-1-RESULTADO.md](05-FASE-1-RESULTADO.md) | Resultado verificado de la Fase 1: autenticación, perfil, roles, hallazgos y configuración manual pendiente |
| [06-BUGS-CONOCIDOS.md](06-BUGS-CONOCIDOS.md) | Registro de bugs abiertos, con hipótesis ordenadas y plan de diagnóstico |
| [07-FASE-2A-RESULTADO.md](07-FASE-2A-RESULTADO.md) | Resultado verificado de la Fase 2A: objetivos, categorías, cascada de borrado y decisiones |
| [08-FASE-2B-RESULTADO.md](08-FASE-2B-RESULTADO.md) | Resultado verificado de la Fase 2B: misiones, presupuesto, pantalla "Hoy" y bugs encontrados |
| [09-FASE-3-RESULTADO.md](09-FASE-3-RESULTADO.md) | Resultado de la Fase 3: evidencias sin Storage, cola de subida y el agujero de moderación que se cerró |
| [10-FASE-4-RESULTADO.md](10-FASE-4-RESULTADO.md) | Resultado de la Fase 4: Aura server-authoritative, idempotencia, tope diario, rachas y pantalla de Aura |
| [11-FASE-5-RESULTADO.md](11-FASE-5-RESULTADO.md) | Resultado de la Fase 5: feed paginado, likes idempotentes, comentarios, reportes con auto-ocultado |
| [12-FASE-6-RESULTADO.md](12-FASE-6-RESULTADO.md) | Resultado de la Fase 6: Gemini vía Cloud Function, cuotas, auditoría de costos y plantillas de reserva |
| [13-FASE-7-RESULTADO.md](13-FASE-7-RESULTADO.md) | Resultado de la Fase 7: Open-Meteo y Open Library, cliente HTTP con timeout y reintentos, ubicación sin GPS |
| [14-FASE-8-RESULTADO.md](14-FASE-8-RESULTADO.md) | Resultado de la Fase 8: panel real con guard por claim, moderación auditada, métricas agregadas y dos agujeros de seguridad cerrados |
| [15-FASE-9-RESULTADO.md](15-FASE-9-RESULTADO.md) | Resultado de la Fase 9: bandeja independiente de las push, horario de silencio, agrupación social y recordatorios por hora local |
| [16-FASE-10-RESULTADO.md](16-FASE-10-RESULTADO.md) | Resultado de la Fase 10: barrido de QA, dos callejones sin salida cerrados y el renombrado de `Page<T>` |
| [17-INFORME-FINAL.md](17-INFORME-FINAL.md) | **Informe final**: qué se construyó, qué falta, cómo correrlo y cómo demostrarlo |
| [18-CORRER-SIN-FIREBASE.md](18-CORRER-SIN-FIREBASE.md) | **Cómo ver la app hoy**, con los emuladores locales y sin cuenta de Firebase |

## Decisiones que requieren aprobación

Están marcadas con ⚠️ en los documentos. Resumen:

1. **ADR-002** — Gemini se llama desde Cloud Functions, nunca desde el cliente.
2. **ADR-003** — Aura calculada en el servidor con ledger auditable.
3. **ADR-004** — Roles por custom claims, no por campo en Firestore.
4. **ADR-005** — Misiones en colección plana bajo el usuario, no anidadas bajo el objetivo.
5. **ADR-001** — Monorepo Melos con apps separadas para móvil y admin.
6. **§2.2 del modelo de datos** — Colección `publicProfiles` como proyección pública del perfil.

## Convenciones

- Idioma del código y de los identificadores: **inglés**. Idioma de la UI: **español e inglés** (i18n desde el día 1).
- Ramas: `main` (producción) · `develop` (integración) · `feature/*` · `fix/*`.
- Commits: Conventional Commits.
- Ninguna fase avanza sin aprobación explícita del product owner.
