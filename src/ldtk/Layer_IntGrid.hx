package ldtk;

import dn.M;
import ldtk.Json.TilesetDefJson;
import ldtk.Json.IntGridValueDef;
import ldtk.Json.AutoRuleDef;

class Layer_IntGrid extends ldtk.Layer {
	var valueInfos : Map<Int, { value:Int, identifier:Null<String>, color:UInt }> = new Map();

	/**
		IntGrid integer values, map is based on coordIds
	**/
	public var intGrid : Map<Int,Int> = new Map();

    var _perlin : Null<hxd.Perlin>;

    inline function getPerlin(r:AutoRuleDef):Null<hxd.Perlin> {
		if( r.perlinSeed!=0.0 && _perlin==null ) {
			_perlin = new hxd.Perlin();
			_perlin.normalize = true;
			_perlin.adjustScale(50, 1);
		}

		if( r.perlinSeed==0.0 && _perlin!=null )
			_perlin = null;

		return _perlin;
	}

    public var autoTilesCache :
		Null< Map<Int, // RuleUID
			Map<Int, // CoordID
				// WARNING: x/y don't contain layerDef.pxOffsetX/Y (to avoid the need of a global update when changing these values). They are added in the JSON though.
				Array<{ x:Int, y:Int, flips:Int, srcX:Int, srcY:Int, tid:Int, a:Float }>
			>
		> > = null;


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

    public function applyAllAutoLayerRules() {
		if( isAutoLayer() ) {
			autoTilesCache = new Map();
			applyAllAutoLayerRulesAt(0, 0, cWid, cHei);
		}
	}

    /** Apply all rules to specific cell **/
    public function applyAllAutoLayerRulesAt(cx:Int, cy:Int, wid:Int, hei:Int) {
        if( !isAutoLayer() || !autoLayerRulesCanBeUsed() )
			return;

		if( autoTilesCache==null ) {
			applyAllAutoLayerRules();
			return;
		}

		//var maxRadius = Std.int( Layer.MAX_AUTO_PATTERN_SIZE*0.5 );
		// Adjust bounds to also redraw nearby cells
		var left = dn.M.imax( 0, cx - wid );
		var right = dn.M.imin( cWid, cx + wid);
		var top = dn.M.imax( 0, cy - hei );
		var bottom = dn.M.imin( cHei, cy + hei);


		// Apply rules
		var source = type==IntGrid ? this : null; //defJson.autoSourceLayerDefUid!=null ? level.getLayerInstance(defJson.autoSourceLayerDefUid) : 
		if( source==null )
			return;

        iterateActiveRulesInEvalOrder( this, (r)->{
			for(x in left...right+1)
			for(y in top...bottom+1)
				applyAutoLayerRuleAt(source, r, x,y);
		});

		// Discard using break-on-match flag
		applyBreakOnMatchesArea(left,top, right-left+1, bottom-top+1);
    }

    public function autoLayerRulesCanBeUsed() {
		if( !isAutoLayer() )
			return false;

		if( defJson.tilesetDefUid==null )
			return false;

		if( type==AutoLayer/* && autoSourceLayerDefUid==null */) //TODO
			return false;

		return true;
	}

    function applyAutoLayerRuleAt(source:Layer_IntGrid, r:AutoRuleDef, cx:Int, cy:Int) : Bool {
		if( !autoLayerRulesCanBeUsed() )
			return false;
		else {
			// Init
			if( !autoTilesCache.exists(r.uid) )
				autoTilesCache.set( r.uid, [] );
			autoTilesCache.get(r.uid).remove( coordId(cx,cy) );

			// Modulos
			if(r.checker!="Vertical" && (cy-r.yOffset) % r.yModulo!=0 )
				return false;

			if( r.checker=="Vertical" && ( cy + ( Std.int(cx/r.xModulo)%2 ) )%r.yModulo!=0 )
				return false;

			if( r.checker!="Horizontal" && (cx-r.xOffset) % r.xModulo!=0 )
				return false;

			if( r.checker=="Horizontal" && ( cx + ( Std.int(cy/r.yModulo)%2 ) )%r.xModulo!=0 )
				return false;


			// Apply rule
			var matched = false;
			if( matches(r, this, source, cx,cy) ) {
				addRuleTilesAt(r, cx,cy, 0);
				matched = true;
			}

			if( ( !matched || !r.breakOnMatch ) && r.flipX && matches(r, this, source, cx,cy, -1) ) {
				addRuleTilesAt(r, cx,cy, 1);
				matched = true;
			}

			if( ( !matched || !r.breakOnMatch ) && r.flipY && matches(r, this, source, cx,cy, 1, -1) ) {
				addRuleTilesAt(r, cx,cy, 2);
				matched = true;
			}

			if( ( !matched || !r.breakOnMatch ) && r.flipX && r.flipY && matches(r, this, source, cx,cy, -1, -1) ) {
				addRuleTilesAt(r, cx,cy, 3);
				matched = true;
			}

			return matched;
		}
	}

    public function matches(r:AutoRuleDef, li:Layer, source:Layer_IntGrid, cx:Int, cy:Int, dirX=1, dirY=1) {
		if( r.tileIds.length==0 )
			return false;

		if( r.chance<=0 || r.chance<1 && dn.M.randSeedCoords(li.json.seed+r.uid, cx,cy, 100) >= r.chance*100 )
			return false;

		if( r.perlinActive && getPerlin(r).perlin(Std.int(li.json.seed+r.perlinSeed), cx*r.perlinScale, cy*r.perlinScale, Std.int(r.perlinOctaves)) < 0 )
			return false;

		// Rule check
		var value : Null<Int> = 0;
		var valueInf : Null<IntGridValueDef> = null;
		var radius = Std.int( r.size/2 );
		for(px in 0...r.size)
		for(py in 0...r.size) {
			var coordId = px + py*r.size;
			if( r.pattern[coordId]==0 )
				continue;

			value = source.isValid( cx+dirX*(px-radius), cy+dirY*(py-radius) )
				? source.getIntGrid( cx+dirX*(px-radius), cy+dirY*(py-radius) )
				: r.outOfBoundsValue;

			if( value==null )
				return false;

			if( dn.M.iabs( r.pattern[coordId] ) == Layer.AUTO_LAYER_ANYTHING ) {
				// "Anything" checks
				if( r.pattern[coordId]>0 && value==0 )
					return false;

				if( r.pattern[coordId]<0 && value!=0 )
					return false;
			}
			else if( dn.M.iabs( r.pattern[coordId] ) > 999 ) {
				// Group checks
				valueInf = source.getIntGridValueDef(value);
				if( r.pattern[coordId]>0 && ( valueInf==null || valueInf.groupUid != Std.int(r.pattern[coordId]/1000)-1 ) )
					return false;

				if( r.pattern[coordId]<0 && ( valueInf!=null && valueInf.groupUid == Std.int(-r.pattern[coordId]/1000)-1 ) )
					return false;
			}
			else {
				// Specific value checks
				if( r.pattern[coordId]>0 && value != r.pattern[coordId] )
					return false;

				if( r.pattern[coordId]<0 && value == -r.pattern[coordId] )
					return false;
			}
		}
		return true;
	}

    public inline function getIntGridValueDef(value:Int) : Null<IntGridValueDef> {
		var out : Null<IntGridValueDef> = null;
		for(v in defJson.intGridValues)
			if( v.value==value ) {
				out = v;
				break;
			}
		return out;
	}

    public inline function getIntGrid(cx:Int, cy:Int) : Int {
		requireType(IntGrid);
		return !isValid(cx,cy) || !intGrid.exists( coordId(cx,cy) ) ? 0 : intGrid.get( coordId(cx,cy) );
	}

    inline function requireType(t:ldtk.Json.LayerType) {
		if( type!=t )
			throw 'Only works on $t layer!';
	}

    inline function addRuleTilesAt(r:AutoRuleDef, cx:Int, cy:Int, flips:Int) {
		var tileIds = r.tileMode=="Single" ? [ getRandomTileForCoord(r, seed, cx,cy, flips) ] : r.tileIds;
		var td = getTilesetDef();
		var stampInfos = r.tileMode=="Single" ? null : getRuleStampRenderInfos(r, td, tileIds, flips);

		//if( !autoTilesCache.get(r.uid).exists( coordId(cx,cy) ) ) //reset whatever is already there to replace it
			autoTilesCache.get(r.uid).set( coordId(cx,cy), [] );

		autoTilesCache.get(r.uid).set( coordId(cx,cy), autoTilesCache.get(r.uid).get( coordId(cx,cy) ).concat(
			tileIds.map( (tid)->{
				return {
					x: cx*defJson.gridSize + (stampInfos==null ? 0 : stampInfos.get(tid).xOff ) + getXOffsetForCoord(r, seed,cx,cy, flips),
					y: cy*defJson.gridSize + (stampInfos==null ? 0 : stampInfos.get(tid).yOff ) + getYOffsetForCoord(r, seed,cx,cy, flips),
					srcX: getTileSourceX(td, tid),
					srcY: getTileSourceY(td, tid),
					tid: tid,
					flips: flips,
					a: r.alpha,
				}
			} )
		));
	}

    public inline function getTileSourceX(td:TilesetDefJson, tileId:Int) {
		return td.padding + getTileCx(td, tileId) * ( td.tileGridSize + td.spacing );
	}

    public inline function getTileSourceY(td:TilesetDefJson, tileId:Int) {
		return td.padding + getTileCy(td, tileId) * ( td.tileGridSize + td.spacing );
	}

    public inline function getTileCx(td:TilesetDefJson, tileId:Int) {
		return tileId - td.__cWid * Std.int( tileId / td.__cWid );
	}

	public inline function getTileCy(td:TilesetDefJson, tileId:Int) {
		return Std.int( tileId / cWid );
	}

    public function getXOffsetForCoord(r:AutoRuleDef, seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return ( M.hasBit(flips,0)?-1:1 ) * ( r.tileXOffset + (
			r.tileRandomXMin==0 && r.tileRandomXMax==0
				? 0
				: dn.M.randSeedCoords( r.uid+seed+flips, cx,cy, (r.tileRandomXMax-r.tileRandomXMin+1) ) + r.tileRandomXMin
		));
	}

    public function getYOffsetForCoord(r:AutoRuleDef, seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return ( M.hasBit(flips,1)?-1:1 ) * ( r.tileYOffset + (
			r.tileRandomYMin==0 && r.tileRandomYMax==0
				? 0
				: dn.M.randSeedCoords( r.uid+seed+1, cx,cy, (r.tileRandomYMax-r.tileRandomYMin+1) ) + r.tileRandomYMin
		));
	}

    public inline function getRuleStampRenderInfos(rule:AutoRuleDef, td:TilesetDefJson, tileIds:Array<Int>, flipBits:Int)
        : Map<Int, { xOff:Int, yOff:Int }> {
            if( td==null )
                return null;
    
            // Get stamp bounds in tileset
            var top = 99999;
            var left = 99999;
            var right = 0;
            var bottom = 0;
            for(tid in tileIds) {
                top = dn.M.imin( top, getTileCy(td, tid) );
                bottom = dn.M.imax( bottom, getTileCy(td, tid) );
                left = dn.M.imin( left, getTileCx(td, tid) );
                right = dn.M.imax( right, getTileCx(td, tid) );
            }
    
            var out = new Map();
            for( tid in tileIds )
                out.set( tid, {
                    xOff: Std.int( ( getTileCx(td, tid)-left - rule.pivotX*(right-left) + defJson.tilePivotX ) * defJson.gridSize ) * (dn.M.hasBit(flipBits,0)?-1:1),
                    yOff: Std.int( ( getTileCy(td, tid)-top - rule.pivotY*(bottom-top) + defJson.tilePivotY ) * defJson.gridSize ) * (dn.M.hasBit(flipBits,1)?-1:1)
                });
            return out;
        }

    public function getRandomTileForCoord(r:AutoRuleDef, seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return r.tileIds[ dn.M.randSeedCoords( r.uid+seed+flips, cx,cy, r.tileIds.length ) ];
	}

    public function applyBreakOnMatchesArea(cx:Int, cy:Int, wid:Int, hei:Int) {
		var left = Std.int(Math.max(0, cx));
		var top = Std.int(Math.max(0,cy));
		var right = Std.int(Math.min(cWid-1, left + wid-1));
		var bottom = Std.int(Math.min(cHei-1, top + hei-1));

		var coordLocks = new Map();

		var td = getTilesetDef();
		for( y in top...bottom+1 )
		for( x in left...right+1 ) {
			iterateActiveRulesInEvalOrder( this, (r)->{
				if( autoTilesCache.exists(r.uid) && autoTilesCache.get(r.uid).exists(coordId(x,y)) ) {
					if( coordLocks.exists( coordId(x,y) ) ) {
						// Tiles below locks are discarded
						autoTilesCache.get(r.uid).remove( coordId(x,y) );
					}
					else if( r.breakOnMatch ) {
						// Break on match is ON
						coordLocks.set( coordId(x,y), true ); // mark cell as locked
					}
					else if( !hasAnyPositionOffset(r) && r.alpha>=1 ) {
						// Check for opaque tiles
						for( t in autoTilesCache.get(r.uid).get( coordId(x,y) ) )
							//if( td.isTileOpaque(t.tid) ) { //TODO
								coordLocks.set( coordId(x,y), true ); // mark cell as locked
								//break;
							//}
					}
				}

			});
		}
	}

    //TODO
    /*public inline function isTileOpaque(td:TilesetDefJson, tid:Int) {
		return td.opaqueTiles!=null ? td.opaqueTiles[tid]==true : false;
	}*/

    public inline function hasAnyPositionOffset(r:AutoRuleDef):Bool {
		return r.tileRandomXMin!=0 || r.tileRandomXMax!=0 || r.tileRandomYMin!=0 || r.tileRandomYMax!=0 || r.tileXOffset!=0 || r.tileYOffset!=0;
	}

    public inline function coordId(cx:Int, cy:Int) {
		return cx + cy*cWid;
	}

    public function iterateActiveRulesInEvalOrder( li:Layer, cbEachRule:(r:AutoRuleDef)->Void ) {
		for(rg in defJson.autoRuleGroups)
			if( li.isRuleGroupActiveHere(rg) )
				for(r in rg.rules)
					if( r.active)
						cbEachRule(r);
	}

    public function getTilesetDef() : Null<TilesetDefJson> {
		var tdUid = getTilesetUid();
		return tdUid==null ? null : untypedProject.getTilesetDefJson(tdUid);
	}

    public function getTilesetUid() : Null<Int> {
		return
			json.overrideTilesetUid!=null ? json.overrideTilesetUid
			: defJson.tilesetDefUid!=null ? defJson.tilesetDefUid
			: null;
	}

    public function isAutoLayer():Bool {
        return type==IntGrid && defJson.tilesetDefUid!=null || type==AutoLayer;
    }

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
