import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

Mission _mission({MissionStatus status = MissionStatus.completed}) => Mission(
  id: 'm1',
  ownerId: 'u1',
  goalId: 'g1',
  title: 'Ver un capítulo en inglés',
  createdAt: DateTime.utc(2026, 8),
  goalTitle: 'Aprender inglés',
  status: status,
  auraReward: 25,
);

Post _post({
  String authorId = 'u1',
  ModerationStatus moderation = ModerationStatus.visible,
}) => Post(
  id: 'p1',
  authorId: authorId,
  type: PostType.reflection,
  text: 'Primera semana completa',
  createdAt: DateTime.utc(2026, 8, 14),
  moderation: moderation,
);

void main() {
  group('validatePost — el feed solo muestra logros reales', () {
    test('un logro SIN referencia se rechaza', () {
      // Es la premisa del producto como regla verificable: sin esto,
      // "completé mi objetivo" sería una frase que cualquiera escribe.
      for (final type in <PostType>[
        PostType.missionCompleted,
        PostType.goalCompleted,
        PostType.milestone,
      ]) {
        final result = validatePost(type: type, text: 'Lo logré');
        expect(
          result.failureOrNull?.messageKey,
          'validation.post.sourceRequired',
          reason: '$type debería exigir una referencia',
        );
      }
    });

    test('una reflexión NO exige referencia', () {
      final result = validatePost(
        type: PostType.reflection,
        text: 'Hoy me costó, pero seguí',
      );
      expect(result.isSuccess, isTrue);
    });

    test('una referencia vacía no cuenta como referencia', () {
      // Mandar un `source` sin ids sería la forma obvia de esquivar la regla.
      final result = validatePost(
        type: PostType.missionCompleted,
        text: 'Listo',
        source: const PostSource(),
      );

      expect(
        result.failureOrNull?.messageKey,
        'validation.post.sourceRequired',
      );
    });

    test('un logro con referencia real se acepta', () {
      final result = validatePost(
        type: PostType.missionCompleted,
        text: '',
        source: sourceFromMission(_mission()),
      );

      // Un logro puede publicarse sin texto: el logro mismo es el contenido.
      expect(result.isSuccess, isTrue);
    });

    test('una reflexión vacía se rechaza', () {
      final result = validatePost(type: PostType.reflection, text: '   ');
      expect(result.failureOrNull?.messageKey, 'validation.post.textRequired');
    });

    test('un texto de más de 500 caracteres se rechaza', () {
      final result = validatePost(
        type: PostType.reflection,
        text: 'a' * (kMaxPostLength + 1),
      );
      expect(result.failureOrNull?.messageKey, 'validation.post.tooLong');
    });

    test('el texto se normaliza', () {
      final result = validatePost(
        type: PostType.reflection,
        text: '  Seguí adelante  ',
      );
      expect(result.valueOrNull, 'Seguí adelante');
    });
  });

  group('sourceFromMission — lo privado no se vuelve público', () {
    test('copia solo títulos, nunca el dueño', () {
      final source = sourceFromMission(_mission());

      expect(source.goalTitle, 'Aprender inglés');
      expect(source.missionTitle, 'Ver un capítulo en inglés');
      expect(source.auraEarned, 25);
      expect(source.isEmpty, isFalse);
    });
  });

  group('canPublishMission', () {
    test('una misión completada se puede publicar', () {
      expect(canPublishMission(_mission()).isSuccess, isTrue);
    });

    test('una misión sin completar NO se puede publicar', () {
      // Publicar algo que no se hizo es exactamente el "logro falso" que el
      // sistema de reportes existe para perseguir.
      final result = canPublishMission(_mission(status: MissionStatus.pending));

      expect(
        result.failureOrNull?.messageKey,
        'validation.post.missionNotCompleted',
      );
    });
  });

  group('validateComment', () {
    test('acepta un comentario normal', () {
      expect(validateComment('  ¡Grande!  ').valueOrNull, '¡Grande!');
    });

    test('rechaza vacío y demasiado largo', () {
      expect(
        validateComment('   ').failureOrNull?.messageKey,
        'validation.comment.required',
      );
      expect(
        validateComment(
          'a' * (kMaxCommentLength + 1),
        ).failureOrNull?.messageKey,
        'validation.comment.tooLong',
      );
    });
  });

  group('validateReport', () {
    test('no se puede reportar el propio contenido', () {
      final result = validateReport(reporterId: 'u1', targetOwnerId: 'u1');
      expect(result.failureOrNull?.messageKey, 'validation.report.ownContent');
    });

    test('reportar contenido ajeno se acepta', () {
      final result = validateReport(
        reporterId: 'u2',
        targetOwnerId: 'u1',
        details: '  Publicación repetida  ',
      );

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, 'Publicación repetida');
    });

    test('un detalle vacío se guarda como nulo', () {
      final result = validateReport(
        reporterId: 'u2',
        targetOwnerId: 'u1',
        details: '   ',
      );
      expect(result.valueOrNull, isNull);
    });
  });

  group('Report.buildId — un reporte por persona y contenido', () {
    test('el id es determinístico', () {
      // La unicidad la da la clave, no una consulta: la misma persona no puede
      // inflar el contador reportando cien veces.
      expect(
        Report.buildId(targetId: 'p1', reporterId: 'u2'),
        Report.buildId(targetId: 'p1', reporterId: 'u2'),
      );
    });

    test('personas distintas producen ids distintos', () {
      expect(
        Report.buildId(targetId: 'p1', reporterId: 'u2'),
        isNot(Report.buildId(targetId: 'p1', reporterId: 'u3')),
      );
    });
  });

  group('Visibilidad y auto-ocultado', () {
    test('el autor ve su contenido aunque esté oculto', () {
      // Esconderle su propio contenido sin explicación lo dejaría creyendo que
      // se perdió.
      final hidden = _post(moderation: ModerationStatus.hidden);

      expect(isPostVisibleFor(hidden, viewerId: 'u1'), isTrue);
      expect(isPostVisibleFor(hidden, viewerId: 'otro'), isFalse);
    });

    test('el admin ve todo, porque para eso modera', () {
      final hidden = _post(moderation: ModerationStatus.hidden);
      expect(isPostVisibleFor(hidden, viewerId: 'root', isAdmin: true), isTrue);
    });

    test('un post visible lo ve cualquiera', () {
      expect(isPostVisibleFor(_post(), viewerId: 'otro'), isTrue);
    });

    test('tres reportes ocultan el contenido de forma preventiva', () {
      expect(shouldAutoHide(2), isFalse);
      expect(shouldAutoHide(kReportsToAutoHide), isTrue);
      expect(shouldAutoHide(10), isTrue);
    });
  });

  group('ReportStatus', () {
    test('un estado desconocido queda abierto, no resuelto', () {
      // Degradar a "resuelto" haría desaparecer reportes reales de la cola.
      expect(ReportStatus.fromWire('inventado'), ReportStatus.open);
      expect(ReportStatus.fromWire(null), ReportStatus.open);
    });

    test('open y reviewing siguen pendientes', () {
      expect(ReportStatus.open.isPending, isTrue);
      expect(ReportStatus.reviewing.isPending, isTrue);
      expect(ReportStatus.resolved.isPending, isFalse);
    });
  });
}
