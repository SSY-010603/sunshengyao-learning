import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[EntryAbility] onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('[EntryAbility] onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error(`Failed to load content: ${JSON.stringify(err)}`);
        return;
      }
      console.info('[EntryAbility] loadContent succeeded');
    });
  }

  onDestroy(): void {
    console.info('[EntryAbility] onDestroy');
  }

  onForeground(): void {
    console.info('[EntryAbility] onForeground');
  }

  onBackground(): void {
    console.info('[EntryAbility] onBackground');
  }
}
