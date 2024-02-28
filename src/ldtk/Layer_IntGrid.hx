package ldtk;

import ldtk.Json.AutoRuleDef;

class Layer_IntGrid extends ldtk.Layer {
	var valueInfos : Map<Int, { value:Int, identifier:Null<String>, color:UInt }> = new Map();

	public function new(p,json) {
		super(p,json);

		if( json.intGridCsv!=null ) {
			// Read new CSV format
			for(i in 0...json.intGridCsv.length)
				if( json.intGridCsv[i]>=0 )
					intGrid.set(i, json.intGridCsv[i]);
		}
		else {
			// Read old pre-CSV format
			for(ig in json.intGrid)
				intGrid.set(ig.coordId, ig.v+1);
		}
	}

	/**
		Get the Integer value at selected coordinates

		Return -1 if none.
	**/
	public inline function getInt(cx:Int, cy:Int) {
		return isCoordValid(cx,cy) ? intGrid.get( getCoordId(cx,cy) ) : 0;
		// return !isCoordValid(cx,cy) || !intGrid.exists( getCoordId(cx,cy) ) ? 0 : intGrid.get( getCoordId(cx,cy) );
	}

	/**
		Return TRUE if there is any value at selected coordinates.

		Optional parameter "val" allows to check for a specific integer value.
	**/
	public inline function hasValue(cx:Int, cy:Int, val=0) {
		return !isCoordValid(cx,cy)
			? false
			: val==0
				? intGrid.get( getCoordId(cx,cy) )>0
				: intGrid.get( getCoordId(cx,cy) )==val;
	}


	inline function getValueInfos(v:Int) {
		return valueInfos.get(v);
	}

	/**
		Get the value String identifier at selected coordinates.

		Return null if none.
	**/
	public inline function getName(cx:Int, cy:Int) : Null<String> {
		return !hasValue(cx,cy) ? null : getValueInfos(getInt(cx,cy)).identifier;
	}

	/**
		Get the value color (0xrrggbb Unsigned-Int format) at selected coordinates.

		Return null if none.
	**/
	public inline function getColorInt(cx:Int, cy:Int) : Null<UInt> {
		return !hasValue(cx,cy) ? null : getValueInfos(getInt(cx,cy)).color;
	}

	/**
		Get the value color ("#rrggbb" string format) at selected coordinates.

		Return null if none.
	**/
	public inline function getColorHex(cx:Int, cy:Int) : Null<String> {
		return !hasValue(cx,cy) ? null : ldtk.Project.intToHex( getValueInfos(getInt(cx,cy)).color );
	}

    public function getRandomTileForCoord(r:AutoRuleDef, seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return r.tileIds[ dn.M.randSeedCoords( r.uid+seed+flips, cx,cy, r.tileIds.length ) ];
	}

    //TODO
    /*public inline function isTileOpaque(td:TilesetDefJson, tid:Int) {
		return td.opaqueTiles!=null ? td.opaqueTiles[tid]==true : false;
	}*/

    public inline function iterateActiveRulesInDisplayOrder( li:Layer, cbEachRule:(r:AutoRuleDef)->Void ) {
		var ruleGroupIdx = defJson.autoRuleGroups.length-1;
		while( ruleGroupIdx>=0 ) {
			// Groups
			if( li.isRuleGroupActiveHere(defJson.autoRuleGroups[ruleGroupIdx]) ) {
				var rg = defJson.autoRuleGroups[ruleGroupIdx];
				var ruleIdx = rg.rules.length-1;
				while( ruleIdx>=0 ) {
					// Rules
					if( rg.rules[ruleIdx].active )
						cbEachRule( rg.rules[ruleIdx] );

					ruleIdx--;
				}
			}
			ruleGroupIdx--;
		}
	}

}
