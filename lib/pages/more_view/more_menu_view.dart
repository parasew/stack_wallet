import 'package:flutter/material.dart';

import '../../themes/stack_colors.dart';
import '../../utilities/assets.dart';
import '../../utilities/text_styles.dart';
import '../../widgets/background.dart';
import '../../widgets/custom_buttons/app_bar_icon_button.dart';
import '../../widgets/rounded_white_container.dart';
import '../settings_views/sub_widgets/settings_list_button.dart';
import 'gift_cards_view.dart';
import 'services_view.dart';

class MoreMenuView extends StatelessWidget {
  const MoreMenuView({super.key});

  static const String routeName = "/moreMenu";

  @override
  Widget build(BuildContext context) {
    return Background(
      child: Scaffold(
        backgroundColor: Theme.of(context).extension<StackColors>()!.background,
        appBar: AppBar(
          leading: AppBarBackButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: Text("More", style: STextStyles.navBarTitle(context)),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (builderContext, constraints) {
              return Padding(
                padding: const EdgeInsets.only(left: 12, top: 12, right: 12),
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 24,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            RoundedWhiteContainer(
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                children: [
                                  SettingsListButton(
                                    iconAssetName: Assets.svg.circleSliders,
                                    iconSize: 16,
                                    title: "Services",
                                    onPressed: () {
                                      Navigator.of(
                                        context,
                                      ).pushNamed(ServicesView.routeName);
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  SettingsListButton(
                                    iconAssetName: Assets.svg.creditCard,
                                    iconSize: 16,
                                    title: "Gift cards",
                                    onPressed: () {
                                      Navigator.of(
                                        context,
                                      ).pushNamed(GiftCardsView.routeName);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
