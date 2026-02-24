import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';

import '../../themes/stack_colors.dart';
import '../../utilities/assets.dart';
import '../settings/settings_menu_item.dart';

final selectedMoreMenuItemStateProvider = StateProvider<int>((_) => 0);

class MoreMenu extends ConsumerStatefulWidget {
  const MoreMenu({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _MoreMenuState();
}

class _MoreMenuState extends ConsumerState<MoreMenu> {
  final List<String> labels = ["Services", "Gift cards"];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < labels.length; i++)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i > 0) const SizedBox(height: 2),
                    SettingsMenuItem<int>(
                      icon: SvgPicture.asset(
                        Assets.svg.polygon,
                        width: 11,
                        height: 11,
                        color:
                            ref
                                    .watch(
                                      selectedMoreMenuItemStateProvider.state,
                                    )
                                    .state ==
                                i
                            ? Theme.of(
                                context,
                              ).extension<StackColors>()!.accentColorBlue
                            : Colors.transparent,
                      ),
                      label: labels[i],
                      value: i,
                      group: ref
                          .watch(selectedMoreMenuItemStateProvider.state)
                          .state,
                      onChanged: (newValue) =>
                          ref
                                  .read(selectedMoreMenuItemStateProvider.state)
                                  .state =
                              newValue,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
