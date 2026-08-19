import { describe, expect, it } from 'vitest';
import {
  HANDLE_PATTERN,
  MAX_DISPLAY_NAME_LENGTH,
  RESERVED_HANDLES,
  normalizeHandle,
  registerProfileSchema,
  setUserRoleSchema,
} from '../src/lib/validation';

/**
 * Estas validaciones son la única frontera real: una función llamable se puede
 * invocar con `curl` y un token válido, sin pasar nunca por nuestra app. Lo que
 * no se rechace acá, entra.
 */
describe('normalizeHandle', () => {
  it('pasa a minúsculas y recorta espacios', () => {
    expect(normalizeHandle('  SanTino  ')).toBe('santino');
  });

  it('hace que la unicidad sea insensible a mayúsculas', () => {
    // Sin esto, @Santino y @santino serían documentos distintos y quedarían
    // dos cuentas indistinguibles a simple vista.
    expect(normalizeHandle('SANTINO')).toBe(normalizeHandle('santino'));
  });
});

describe('registerProfileSchema', () => {
  const valid = { displayName: 'Santino', handle: 'santino' };

  it('acepta un registro válido', () => {
    const result = registerProfileSchema.safeParse(valid);
    expect(result.success).toBe(true);
  });

  it('normaliza el handle al validarlo', () => {
    const result = registerProfileSchema.safeParse({
      ...valid,
      handle: '  SanTino ',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.handle).toBe('santino');
    }
  });

  it('recorta el nombre visible', () => {
    const result = registerProfileSchema.safeParse({
      ...valid,
      displayName: '  Santino  ',
    });
    expect(result.success && result.data.displayName).toBe('Santino');
  });

  it('rechaza un nombre vacío', () => {
    expect(
      registerProfileSchema.safeParse({ ...valid, displayName: '   ' }).success
    ).toBe(false);
  });

  it('rechaza un nombre más largo que el límite', () => {
    expect(
      registerProfileSchema.safeParse({
        ...valid,
        displayName: 'x'.repeat(MAX_DISPLAY_NAME_LENGTH + 1),
      }).success
    ).toBe(false);
  });

  it.each([
    ['ab', 'demasiado corto'],
    ['x'.repeat(21), 'demasiado largo'],
    ['con espacio', 'espacios'],
    ['Con-Guion', 'guion medio'],
    ['acento_ñ', 'caracteres no ASCII'],
    ['emoji🔥', 'emoji'],
  ])('rechaza el handle %s (%s)', (handle) => {
    expect(registerProfileSchema.safeParse({ ...valid, handle }).success).toBe(
      false
    );
  });

  it.each(['santino', 'ana_gomez', 'user123', 'abc'])(
    'acepta el handle %s',
    (handle) => {
      expect(
        registerProfileSchema.safeParse({ ...valid, handle }).success
      ).toBe(true);
    }
  );

  it('rechaza los handles reservados', () => {
    // Sin esto, la primera persona en registrarse se queda con @admin o
    // @soporte y puede suplantar al equipo en el feed.
    for (const handle of ['admin', 'soporte', 'ascend', 'staff']) {
      expect(
        registerProfileSchema.safeParse({ ...valid, handle }).success
      ).toBe(false);
    }
  });

  it('rechaza los reservados también escritos en mayúsculas', () => {
    expect(
      registerProfileSchema.safeParse({ ...valid, handle: 'ADMIN' }).success
    ).toBe(false);
  });

  it('rechaza un locale no soportado', () => {
    expect(
      registerProfileSchema.safeParse({ ...valid, locale: 'fr' }).success
    ).toBe(false);
  });

  it('acepta que no vengan locale ni timezone', () => {
    expect(registerProfileSchema.safeParse(valid).success).toBe(true);
  });

  it('rechaza entradas que no son objetos', () => {
    for (const input of [null, undefined, 'texto', 42, []]) {
      expect(registerProfileSchema.safeParse(input).success).toBe(false);
    }
  });
});

describe('setUserRoleSchema', () => {
  it('acepta los dos roles del sistema', () => {
    for (const role of ['user', 'admin']) {
      expect(
        setUserRoleSchema.safeParse({ targetUid: 'abc', role }).success
      ).toBe(true);
    }
  });

  it('rechaza un rol inventado', () => {
    // Si esto pasara, se podría firmar un claim con un rol que ninguna regla
    // contempla y el comportamiento quedaría indefinido.
    expect(
      setUserRoleSchema.safeParse({ targetUid: 'abc', role: 'superadmin' })
        .success
    ).toBe(false);
  });

  it('exige un uid destino no vacío', () => {
    expect(
      setUserRoleSchema.safeParse({ targetUid: '   ', role: 'admin' }).success
    ).toBe(false);
  });
});

describe('coherencia con el cliente', () => {
  it('el patrón de handle es el mismo que el de Validators en Dart', () => {
    // Duplicado a propósito: validar solo en el cliente no es validar. Este
    // test existe para que las dos copias no se separen en silencio.
    expect(HANDLE_PATTERN.source).toBe('^[a-z0-9_]{3,20}$');
  });

  it('la lista de reservados no está vacía', () => {
    expect(RESERVED_HANDLES.size).toBeGreaterThan(0);
    expect(RESERVED_HANDLES.has('admin')).toBe(true);
  });
});
