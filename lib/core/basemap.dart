import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'app_colors.dart';
import 'map_config.dart';

/// Подложка 2ГИС для всех flutter_map-экранов.
///
/// Собрана в один слой не ради красоты: раньше каждый экран заводил свой
/// `TileLayer`, и когда тайлы не приходили (403 на ключ, недоступный
/// tile*.maps.2gis.com), карта оставалась ровным серым прямоугольником — без
/// сообщения, без повтора, без следа в логе. Охранник видел «карта не
/// загрузилась» и не мог ничего сделать, а мы не могли понять, что случилось.
///
/// Теперь ошибки тайлов видны: в логе — адрес и причина, на карте — плашка с
/// кнопкой «Повторить», которая пересоздаёт слой и заново тянет тайлы.
class BaseMapLayer extends StatefulWidget {
  const BaseMapLayer({super.key, this.showRetry = true});

  /// Показывать плашку «Карта не загрузилась» с повтором. На маленьких
  /// карточках (деталка инцидента) плашка мешает, там достаточно лога.
  final bool showRetry;

  @override
  State<BaseMapLayer> createState() => _BaseMapLayerState();
}

class _BaseMapLayerState extends State<BaseMapLayer> {
  /// Меняется при повторе — новый ключ заставляет flutter_map выбросить
  /// сломанный слой вместе с его кэшем ошибок и запросить тайлы заново.
  int _attempt = 0;
  int _failures = 0;
  bool _loggedFirstFailure = false;

  void _onTileError(TileImage tile, Object error, StackTrace? _) {
    if (!_loggedFirstFailure) {
      _loggedFirstFailure = true;
      debugPrint(
        '[basemap] тайл ${tile.coordinates} не загрузился: $error\n'
        '[basemap] шаблон: ${MapConfig.tileUrlTemplate}\n'
        '[basemap] ключ подложки в сборке: ${MapConfig.hasTilesKey ? "есть" : "НЕТ (бесплатная веб-подложка)"}',
      );
    }
    if (mounted) setState(() => _failures++);
  }

  void _retry() => setState(() {
        _attempt++;
        _failures = 0;
        _loggedFirstFailure = false;
      });

  @override
  Widget build(BuildContext context) {
    // Одна-две потери — обычное дело на слабой связи, flutter_map дотянет их
    // сам. Плашку показываем, когда не пришёл уже целый экран тайлов.
    final failed = widget.showRetry && _failures >= 4;

    return Stack(
      children: [
        TileLayer(
          key: ValueKey(_attempt),
          urlTemplate: MapConfig.tileUrlTemplate,
          subdomains: MapConfig.tileSubdomains,
          maxNativeZoom: MapConfig.tileMaxNativeZoom,
          userAgentPackageName: MapConfig.userAgentPackageName,
          errorTileCallback: _onTileError,
        ),
        // Ниже центра: в центре карточки стоит маркер охранника, а над ним —
        // плашка адреса, и плашка повтора закрывала оба.
        if (failed)
          Align(
            alignment: const Alignment(0, 0.55),
            child: _RetryChip(onTap: _retry),
          ),
        const MapAttribution(),
      ],
    );
  }
}

class _RetryChip extends StatelessWidget {
  const _RetryChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.cardDark.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh, size: 16, color: AppColors.textPrimary),
                SizedBox(width: 6),
                Text(
                  'Карта не загрузилась. Повторить',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Подпись правообладателя подложки.
///
/// Вместо flutter_map-овского `SimpleAttributionWidget`: тот жёстко впечатывает
/// «flutter_map | © » перед нашим текстом (см. его исходник), из-за чего на
/// карте висела строка «flutter_map | © 2ГИС» — имя библиотеки в интерфейсе
/// охранника. Лицензия 2ГИС требует только их знак, поэтому оставляем «© 2ГИС».
class MapAttribution extends StatelessWidget {
  /// Слева внизу: справа на карточке карты стоят кнопки зума и «на весь
  /// экран», и подпись пряталась за ними.
  const MapAttribution({super.key, this.alignment = Alignment.bottomLeft});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(
                MapConfig.attribution,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      );
}
