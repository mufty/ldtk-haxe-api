package ldtk;

import ldtk.Json.AutoLayerRuleGroupJson;

class AutoLayerRuleGroup {

    public var defJson:AutoLayerRuleGroupJson;

    public var rules: Array<AutoRule> = new Array<AutoRule>();

    public function new(rg:AutoLayerRuleGroupJson){
        defJson = rg;
    }

}