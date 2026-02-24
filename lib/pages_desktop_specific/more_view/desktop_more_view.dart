import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../route_generator.dart';
import '../../themes/stack_colors.dart';
import '../../utilities/text_styles.dart';
import '../../widgets/desktop/desktop_app_bar.dart';
import '../../widgets/desktop/desktop_scaffold.dart';
import 'more_menu.dart';
import 'sub_widgets/desktop_gift_cards_view.dart';
import 'sub_widgets/desktop_services_view.dart';

class DesktopMoreView extends ConsumerStatefulWidget {
  const DesktopMoreView({super.key});

  static const String routeName = "/desktopMore";

  @override
  ConsumerState<DesktopMoreView> createState() => _DesktopMoreViewState();
}

class _DesktopMoreViewState extends ConsumerState<DesktopMoreView> {
  final List<Widget> contentViews = [
    const Navigator(
      key: Key("moreServicesDesktopKey"),
      onGenerateRoute: RouteGenerator.generateRoute,
      initialRoute: DesktopServicesView.routeName,
    ),
    const Navigator(
      key: Key("moreGiftCardsDesktopKey"),
      onGenerateRoute: RouteGenerator.generateRoute,
      initialRoute: DesktopGiftCardsView.routeName,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DesktopScaffold(
      background: Theme.of(context).extension<StackColors>()!.background,
      appBar: const DesktopAppBar(
        isCompactHeight: true,
        leading: Row(
          children: [SizedBox(width: 24, height: 24), DesktopMoreTitle()],
        ),
      ),
      body: Row(
        children: [
          const Padding(
            padding: EdgeInsets.all(15.0),
            child: Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(child: MoreMenu()),
            ),
          ),
          Expanded(
            child:
                contentViews[ref
                    .watch(selectedMoreMenuItemStateProvider.state)
                    .state],
          ),
        ],
      ),
    );
  }
}

class DesktopMoreTitle extends StatelessWidget {
  const DesktopMoreTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Text("More", style: STextStyles.desktopH3(context));
  }
}
