/// Región donde viven las Cloud Functions.
///
/// Vive en una constante y no escrita a mano en cada llamada porque **tiene que
/// coincidir exactamente con `REGION` de `backend/functions/src/config/
/// constants.ts`**. Un desajuste no da un error que explique nada: da un
/// `not-found` genérico, como si la función no existiera, y cuesta horas de
/// diagnosticar.
const String kFunctionsRegion = 'southamerica-east1';
