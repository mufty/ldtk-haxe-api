package ldtk;

import ldtk.Json.AutoRuleDef;

class AutoRule {

    public static var AUTO_LAYER_ANYTHING = 1000001;

    public var defJson:AutoRuleDef;

    var explicitlyRequiredValues : Array<Int> = [];

    public var radius(get,never) : Int; inline function get_radius() return defJson.size<=1 ? 1 : Std.int(defJson.size*0.5);

    public function new(r:AutoRuleDef){
        defJson = r;

        updateUsedValues();
    }

    public function updateUsedValues() {
		explicitlyRequiredValues = [];
		for(v in defJson.pattern)
			if( v>0 && v!=AUTO_LAYER_ANYTHING && !explicitlyRequiredValues.contains(v) )
				explicitlyRequiredValues.push(v);
	}

    public function isRelevantInLayerAt(sourceLi:Layer, cx:Int, cy:Int) {
		for(v in explicitlyRequiredValues) {
			if( !sourceLi.containsIntGridValueOrGroup(v) )
				return false;
			else if( defJson.size==1 && !sourceLi.hasIntGridValueInArea(v,cx,cy) )
				return false;
			else if( defJson.size>1
				&& !sourceLi.hasIntGridValueInArea(v,cx-radius,cy-radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx+radius,cy-radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx+radius,cy+radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx-radius,cy+radius) )
					return false;
		}
		return true;
	}

}