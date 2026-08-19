/**
 * Validaciones de entrada de las funciones llamables.
 *
 * Replican, campo por campo, las de `Validators` en `ascend_core`. La
 * duplicación es deliberada y no es deuda: validar solo en el cliente no es
 * validar. Cualquiera puede invocar una función llamable con `curl` y un token
 * válido, sin pasar por nuestra app.
 *
 * Si cambia una regla acá, tiene que cambiar en `packages/ascend_core/lib/src/
 * validators/validators.dart`. Hay un test que compara ambos conjuntos de
 * casos límite para que no se separen en silencio.
 */

import { z } from 'zod';

/** Longitud máxima del nombre visible. Coincide con `maxDisplayNameLength`. */
export const MAX_DISPLAY_NAME_LENGTH = 40;

/** Longitud máxima de la biografía. */
export const MAX_BIO_LENGTH = 160;

/** Formato del handle: minúsculas, números y guion bajo, de 3 a 20. */
export const HANDLE_PATTERN = /^[a-z0-9_]{3,20}$/;

/**
 * Handles que nadie puede reclamar.
 *
 * Sin esto, la primera persona que se registre puede quedarse con `@admin` o
 * `@ascend` y suplantar al equipo en el feed. Recuperarlo después implica
 * quitarle el nombre a alguien, que siempre sale mal.
 */
export const RESERVED_HANDLES: ReadonlySet<string> = new Set([
  'admin',
  'administrator',
  'ascend',
  'ascendapp',
  'soporte',
  'support',
  'ayuda',
  'help',
  'root',
  'system',
  'sistema',
  'moderador',
  'moderator',
  'staff',
  'equipo',
  'team',
  'oficial',
  'official',
  'null',
  'undefined',
  'me',
  'yo',
]);

/**
 * Normaliza un handle a su forma canónica.
 *
 * La unicidad tiene que ser insensible a mayúsculas: si `@Santino` y
 * `@santino` fueran documentos distintos, dos personas podrían tener nombres
 * indistinguibles a simple vista, que es exactamente el vector de suplantación
 * que queremos cerrar.
 */
export function normalizeHandle(input: string): string {
  return input.trim().toLowerCase();
}

/** Esquema de entrada de `registerProfile`. */
export const registerProfileSchema = z.object({
  displayName: z
    .string()
    .trim()
    .min(1, 'El nombre no puede estar vacío.')
    .max(MAX_DISPLAY_NAME_LENGTH, 'El nombre es demasiado largo.'),
  handle: z
    .string()
    .transform(normalizeHandle)
    .refine((value) => HANDLE_PATTERN.test(value), {
      message: 'Usá entre 3 y 20 caracteres: letras, números y guion bajo.',
    })
    .refine((value) => !RESERVED_HANDLES.has(value), {
      message: 'Ese nombre de usuario está reservado.',
    }),
  locale: z.enum(['es', 'en']).optional(),
  timezone: z.string().trim().min(1).max(64).optional(),
});

/** Entrada validada de `registerProfile`. */
export type RegisterProfileInput = z.infer<typeof registerProfileSchema>;

/** Esquema de entrada de `setUserRole`. */
export const setUserRoleSchema = z.object({
  targetUid: z.string().trim().min(1).max(128),
  role: z.enum(['user', 'admin']),
  reason: z.string().trim().max(280).optional(),
});

/** Entrada validada de `setUserRole`. */
export type SetUserRoleInput = z.infer<typeof setUserRoleSchema>;

/** Esquema de entrada de `setUserStatus`. */
export const setUserStatusSchema = z.object({
  targetUid: z.string().trim().min(1).max(128),
  status: z.enum(['active', 'suspended']),
  // El motivo es obligatorio al suspender y se valida abajo: una suspensión
  // sin motivo es una decisión que después nadie puede revisar.
  reason: z.string().trim().max(280).optional(),
});

/** Entrada validada de `setUserStatus`. */
export type SetUserStatusInput = z.infer<typeof setUserStatusSchema>;

/** Esquema de entrada de `moderateContent`. */
export const moderateContentSchema = z.object({
  reportId: z.string().trim().min(1).max(256),
  action: z.enum(['hide_content', 'dismiss', 'suspend_author']),
  note: z.string().trim().max(500).optional(),
});

/** Entrada validada de `moderateContent`. */
export type ModerateContentInput = z.infer<typeof moderateContentSchema>;
