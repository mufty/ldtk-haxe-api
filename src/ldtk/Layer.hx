package ldtk;

import dn.M;
import ldtk.Json;

class Layer {

    public static var allLayerInstances:Array<Layer> = new Array<Layer>();
    public static var MAX_AUTO_PATTERN_SIZE = 9;
    public static var AUTO_LAYER_ANYTHING = 1000001;
	var untypedProject: ldtk.Project;

	/** Original JSON object **/
	public var json(default,null) : LayerInstanceJson;

	/** Original layer definition JSON object **/
	public var defJson(default,null) : LayerDefJson;

	public var identifier : String;
	public var type : LayerType;

	/** Unique instance identifier **/
	public var iid : String;

	/** Layer instance visibility **/
	public var visible : Bool;

	/** Grid size in pixels **/
	public var gridSize : Int;

	/** Grid-based layer width **/
	public var cWid : Int;
	/** Grid-based layer height **/
	public var cHei : Int;

	/** Pixel-based layer width **/
	public var pxWid : Int;
	/** Pixel-based layer height **/
	public var pxHei : Int;

	/**
		Pixel-based layer X offset (includes both instance and definition offsets)
	**/
	public var pxTotalOffsetX: Int;

	/**
		Pixel-based layer Y offset (includes both instance and definition offsets)
	**/
	public var pxTotalOffsetY : Int;

	/** Layer opacity (0-1) **/
	public var opacity : Float;

    public var seed : Int;

	/**
		IntGrid integer values, map is based on coordIds
	**/
	public var intGrid : Map<Int,Int> = new Map();

	public var ruleGroups:Array<AutoLayerRuleGroup>;

	var layerIntGridUseCount : Map<Int,Int> = new Map();
	var areaIntGridUseCount : Map<Int, Map<Int,Int>> = new Map();
	var intGridAreaSize = 10;

	public var autoTilesCache :
		Null< Map<Int, // RuleUID
			Map<Int, // CoordID
				// WARNING: x/y don't contain layerDef.pxOffsetX/Y (to avoid the need of a global update when changing these values). They are added in the JSON though.
				Array<{ x:Int, y:Int, flips:Int, srcX:Int, srcY:Int, tid:Int, a:Float }>
			>
		> > = null;

	var explicitlyRequiredValues : Array<Int> = [];

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

	public function new(p:ldtk.Project, json:ldtk.Json.LayerInstanceJson) {
		this.json = json;
		this.defJson = p.getLayerDefJson(json.layerDefUid);
		untypedProject = p;
		identifier = json.__identifier;
		type =
			try LayerType.createByName(json.__type)
			catch(e:Dynamic) throw 'Unknown layer type ${json.__type} in $identifier';
		iid = json.iid;
		gridSize = json.__gridSize;
		cWid = json.__cWid;
		cHei = json.__cHei;
		pxWid = cWid * json.__gridSize;
		pxHei = cHei * json.__gridSize;
		pxTotalOffsetX = json.__pxTotalOffsetX;
		pxTotalOffsetY = json.__pxTotalOffsetY;
		opacity = json.__opacity;
		visible = json.visible==true;

        seed = Std.random(9999999);

		initRules();

		recountAllIntGridValues();

        allLayerInstances.push(this);
	}

	/** Print class debug info **/
	@:keep public function toString() {
		return 'ldtk.Layer[#$identifier, type=$type]';
	}

	public function setIntGrid(cx:Int, cy:Int, v:Int, useAsyncRender:Bool) {
		requireType(IntGrid);
		if( isValid(cx,cy) ) {
			if( v>=0 ) {
				var old = intGrid.get(coordId(cx,cy));
				if( old!=v ) {
					decreaseAreaIntGridValueCount(old, cx,cy);
					increaseAreaIntGridValueCount(v, cx, cy);
					intGrid.set( coordId(cx,cy), v );
				}
				/*if( useAsyncRender )
					asyncPaint(cx,cy, getIntGridValueColor(v));*/
			}
			else
				removeIntGrid(cx,cy, useAsyncRender);
		}
	}

	public function removeIntGrid(cx:Int, cy:Int, useAsyncRender:Bool) {
		requireType(IntGrid);
		if( isValid(cx,cy) && hasIntGrid(cx,cy) ) {
			decreaseAreaIntGridValueCount( intGrid.get(coordId(cx,cy)), cx, cy );
			intGrid.remove( coordId(cx,cy) );
		}
		/*if( useAsyncRender )
			asyncErase(cx,cy);*/
	}

    /*public function asyncErase(cx:Int, cy:Int) {
        #if heaps
        renderTarget.clearTile(cx,cy);
        #end
    }*/

	public function recountAllIntGridValues() {
		if( type!=IntGrid )
			return;

		areaIntGridUseCount = new Map();
		layerIntGridUseCount = new Map();

		for(cy in 0...cHei)
		for(cx in 0...cWid) {
			if( hasIntGrid(cx,cy) )
				increaseAreaIntGridValueCount(getIntGrid(cx,cy), cx, cy);
		}
	}

	function increaseAreaIntGridValueCount(iv:Null<Int>, cx:Int, cy:Int) {
		if( iv==0 || iv==null )
			return;

		if( !areaIntGridUseCount.exists(iv) )
			areaIntGridUseCount.set(iv, new Map());

		var areaCountMap = areaIntGridUseCount.get(iv);
		final cid = areaCoordId(cx,cy);
		if( !areaCountMap.exists(cid) )
			areaCountMap.set(cid,1);
		else
			areaCountMap.set(cid, areaCountMap.get(cid)+1);

		// Layer counts
		if( !layerIntGridUseCount.exists(iv) )
			layerIntGridUseCount.set(iv, 1);
		else
			layerIntGridUseCount.set(iv, layerIntGridUseCount.get(iv)+1);

		// Also update group
		if( iv<1000 ) {
			var groupUid = getIntGridGroupUidFromValue(iv);
			if( groupUid>=0 )
				increaseAreaIntGridValueCount(getRuleValueFromGroupUid(groupUid), cx,cy);
		}
	}

	function decreaseAreaIntGridValueCount(iv:Null<Int>, cx:Int, cy:Int) {
		if( iv!=0 && iv!=null && areaIntGridUseCount.exists(iv) ) {
			var areaCountMap = areaIntGridUseCount.get(iv);
			final cid = areaCoordId(cx,cy);
			if( areaCountMap.exists(cid) ) {
				areaCountMap.set(cid, areaCountMap.get(cid)-1);

				// Last one in area
				if( areaCountMap.get(cid)<=0 )
					areaCountMap.remove(cid);

				// Layer counts
				if( layerIntGridUseCount.exists(iv) ) {
					layerIntGridUseCount.set(iv, layerIntGridUseCount.get(iv)-1);
					// Last one in layer
					if( layerIntGridUseCount.get(iv)<=0 )
						layerIntGridUseCount.remove(iv);
				}
			}
		}

		// Also update group
		if( iv<1000 ) {
			var groupUid = getIntGridGroupUidFromValue(iv);
			if( groupUid>=0 )
				decreaseAreaIntGridValueCount(getRuleValueFromGroupUid(groupUid), cx,cy);
		}
	}

	public inline function getRuleValueFromGroupUid(groupUid:Int) {
		return groupUid<0 ? -1 : ( groupUid + 1 ) * 1000;
	}

	public function getIntGridGroupUidFromValue(intGridValue:Int) : Int {
		return !hasIntGridValue(intGridValue) ? -1 : getIntGridValueDef(intGridValue).groupUid;
	}

	public function hasIntGridValue(v:Int) {
		for(iv in defJson.intGridValues)
			if( iv.value==v )
				return true;
		return false;
	}

	inline function areaCoordId(cx:Int,cy:Int) {
		return Std.int(cx/intGridAreaSize) + Std.int(cy/intGridAreaSize) * 10000;
	}

	public function hasIntGrid(cx:Int, cy:Int) {
		requireType(IntGrid);
		return getIntGrid(cx,cy)!=0;
	}

	/**
		Return TRUE if grid-based coordinates are within layer bounds.
	**/
	public inline function isCoordValid(cx,cy) {
		return cx>=0 && cx<cWid && cy>=0 && cy<cHei;
	}


	inline function getCx(coordId:Int) {
		return coordId - Std.int(coordId/cWid)*cWid;
	}

	inline function getCy(coordId:Int) {
		return Std.int(coordId/cWid);
	}

	inline function getCoordId(cx,cy) return cx+cy*cWid;

    public function isRuleGroupActiveHere(rg:AutoLayerRuleGroupJson) {
		return rg.active && !rg.isOptional || exists(json.optionalRules, rg.uid);
	}

    public function exists(arr:Array<Int>, uid:Int):Bool {
        for(val in arr){
            if(val == uid)
                return true;
        }
        return false;
    }

    public inline function isValid(cx:Int,cy:Int) {
		return cx>=0 && cx<cWid && cy>=0 && cy<cHei;
	}

	public function isAutoLayer():Bool {
        return (type==IntGrid && defJson.tilesetDefUid!=null) || type==AutoLayer;
    }

	public function applyAllRules() {
		if( isAutoLayer() ) {
			clearAllAutoTilesCache();
			applyAllRulesAt(0, 0, cWid, cHei);
		}
	}

	function clearAllAutoTilesCache() {
		autoTilesCache = new Map();
	}

	/** Apply all rules to specific cell **/
    public function applyAllRulesAt(cx:Int, cy:Int, wid:Int, hei:Int) {
        if( !autoLayerRulesCanBeUsed() ) {
			clearAllAutoTilesCache();
			return;
		}

		var source = type==IntGrid ? this : defJson.autoSourceLayerDefUid!=null ? getLayerInstance(defJson.autoSourceLayerDefUid) : null;
		if( source==null ) {
			clearAllAutoTilesCache();
			return;
		}

		if( autoTilesCache==null ) {
			applyAllRules();
			return;
		}

		// Adjust bounds to also redraw nearby cells
		var maxRadius = Std.int( MAX_AUTO_PATTERN_SIZE*0.5 );
		var left = dn.M.imax( 0, cx - maxRadius );
		var right = dn.M.imin( cWid-1, cx + wid-1 + maxRadius );
		var top = dn.M.imax( 0, cy - maxRadius );
		var bottom = dn.M.imin( cHei-1, cy + hei-1 + maxRadius );

		// Apply rules
		iterateActiveRulesInEvalOrder( this, (r)->{
			clearAutoTilesCacheRect(r.defJson, left,top, right-left+1, bottom-top+1);
			for(x in left...right+1)
			for(y in top...bottom+1)
				applyRuleAt(source, r, x,y);
		});

		// Discard using break-on-match flag
		applyBreakOnMatchesArea(left,top, right-left+1, bottom-top+1);
    }

	function clearAutoTilesCacheRect(r:AutoRuleDef, cx,cy,wid,hei) {
		if( !autoTilesCache.exists(r.uid) )
			autoTilesCache.set( r.uid, [] );

		var m = autoTilesCache.get(r.uid);
		for(y in cy...cy+hei)
		for(x in cx...cx+wid)
			m.remove( coordId(x,y) );
	}

    function getLayerInstance(uid:Int){
        var res = null;
        for(li in allLayerInstances){
            if(uid == li.json.layerDefUid){
                res = li;
                break;
			}
        }
        return res;
    }

	public function autoLayerRulesCanBeUsed() {
		if( !isAutoLayer() )
			return false;

		if( defJson.tilesetDefUid==null )
			return false;

		if( type==AutoLayer && defJson.autoSourceLayerDefUid==null)
			return false;

		return true;
	}

	public function iterateActiveRulesInEvalOrder( li:Layer, cbEachRule:(r:AutoRule)->Void ) {
		for(rg in ruleGroups)
			if( li.isRuleGroupActiveHere(rg.defJson) )
				for(r in rg.rules)
					if( r.defJson.active)
						cbEachRule(r);
	}

	public function updateUsedValues(r:AutoRuleDef) {
		explicitlyRequiredValues = [];
		for(v in r.pattern)
			if( v>0 && v!=AUTO_LAYER_ANYTHING && !explicitlyRequiredValues.contains(v) )
				explicitlyRequiredValues.push(v);
	}

	public function initRules(){
		var ruleGroups = new Array<AutoLayerRuleGroup>();
		for(rg in defJson.autoRuleGroups) {
			var group = new AutoLayerRuleGroup(rg);
			for(r in rg.rules) {
				var rule = new AutoRule(r);
				group.rules.push(rule);
			}
			ruleGroups.push(group);
		}

		this.ruleGroups = ruleGroups;
	}

	public function containsIntGridValueOrGroup(iv:Int) {
		return layerIntGridUseCount.exists(iv);
	}

	public inline function hasIntGridValueInArea(iv:Int, cx:Int, cy:Int) {
		return areaIntGridUseCount.exists(iv) && areaIntGridUseCount.get(iv).get(areaCoordId(cx,cy)) > 0;
	}

	function applyRuleAt(sourceLi:Layer, r:AutoRule, cx:Int, cy:Int) : Bool {
		// Skip rule that requires specific IntGrid values absent from layer
		if( !r.isRelevantInLayerAt(sourceLi,cx,cy) )
			return false;

		// Modulos
		if( r.defJson.checker!="Vertical" && (cy-r.defJson.yOffset) % r.defJson.yModulo!=0 )
			return false;

		if( r.defJson.checker=="Vertical" && ( cy + ( Std.int(cx/r.defJson.xModulo)%2 ) )%r.defJson.yModulo!=0 )
			return false;

		if( r.defJson.checker!="Horizontal" && (cx-r.defJson.xOffset) % r.defJson.xModulo!=0 )
			return false;

		if( r.defJson.checker=="Horizontal" && ( cx + ( Std.int(cy/r.defJson.yModulo)%2 ) )%r.defJson.xModulo!=0 )
			return false;

		// Apply rule
		var matched = false;
		if( matches(r.defJson, this, sourceLi, cx,cy) ) {
			addRuleTilesAt(r.defJson, cx,cy, 0);
			matched = true;
		}

		if( ( !matched || !r.defJson.breakOnMatch ) && r.defJson.flipX && matches(r.defJson, this, sourceLi, cx,cy, -1) ) {
			addRuleTilesAt(r.defJson, cx,cy, 1);
			matched = true;
		}

		if( ( !matched || !r.defJson.breakOnMatch ) && r.defJson.flipY && matches(r.defJson, this, sourceLi, cx,cy, 1, -1) ) {
			addRuleTilesAt(r.defJson, cx,cy, 2);
			matched = true;
		}

		if( ( !matched || !r.defJson.breakOnMatch ) && r.defJson.flipX && r.defJson.flipY && matches(r.defJson, this, sourceLi, cx,cy, -1, -1) ) {
			addRuleTilesAt(r.defJson, cx,cy, 3);
			matched = true;
		}

		return matched;
	}

    public function iterateActiveRulesInDisplayOrder( li:Layer, cbEachRule:(r:AutoRuleDef)->Void ) {
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
				if( autoTilesCache.exists(r.defJson.uid) && autoTilesCache.get(r.defJson.uid).exists(coordId(x,y)) ) {
					if( coordLocks.exists( coordId(x,y) ) ) {
						// Tiles below locks are discarded
						autoTilesCache.get(r.defJson.uid).remove( coordId(x,y) );
					}
					else if( r.defJson.breakOnMatch ) {
						// Break on match is ON
						coordLocks.set( coordId(x,y), true ); // mark cell as locked
					}
					else if( !hasAnyPositionOffset(r.defJson) && r.defJson.alpha>=1 ) {
						// Check for opaque tiles
						for( t in autoTilesCache.get(r.defJson.uid).get( coordId(x,y) ) )
							//if( td.isTileOpaque(t.tid) ) { //TODO
								coordLocks.set( coordId(x,y), true ); // mark cell as locked
								//break;
							//}
					}
				}

			});
		}
	}

	public inline function coordId(cx:Int, cy:Int) {
		return cx + cy*cWid;
	}

	public function matches(r:AutoRuleDef, li:Layer, source:Layer, cx:Int, cy:Int, dirX=1, dirY=1) {
		if( r.tileRectsIds.length==0 )
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

	function addRuleTilesAt(r:AutoRuleDef, cx:Int, cy:Int, flips:Int) {
        var tileRectIds = getRandomTileRectIdsForCoord(r, seed, cx,cy, flips);
		var td = getTilesetDef();
		var stampInfos = r.tileMode=="Single" ? null : getRuleStampRenderInfos(r, td, tileRectIds, flips);

		//if( !autoTilesCache.get(r.uid).exists( coordId(cx,cy) ) ) //reset whatever is already there to replace it
			autoTilesCache.get(r.uid).set( coordId(cx,cy), [] );

		autoTilesCache.get(r.uid).set( coordId(cx,cy), autoTilesCache.get(r.uid).get( coordId(cx,cy) ).concat(
			tileRectIds.map( (tid)->{
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

	public inline function hasAnyPositionOffset(r:AutoRuleDef):Bool {
		return r.tileRandomXMin!=0 || r.tileRandomXMax!=0 || r.tileRandomYMin!=0 || r.tileRandomYMax!=0 || r.tileXOffset!=0 || r.tileYOffset!=0;
	}

	public function getIntGrid(cx:Int, cy:Int) : Int {
		requireType(IntGrid);
		return !isValid(cx,cy) || !intGrid.exists( coordId(cx,cy) ) ? 0 : intGrid.get( coordId(cx,cy) );
	}

	inline function requireType(t:ldtk.Json.LayerType) {
		if( type!=t )
			throw 'Only works on $t layer!';
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

	public function getRandomTileRectIdsForCoord(r:AutoRuleDef, seed:Int, cx:Int,cy:Int, flips:Int) : Array<Int> {
		if( r.tileRectsIds.length==0 )
			return [];
		else
			return r.tileRectsIds[ dn.M.randSeedCoords( r.uid+seed+flips, cx,cy, r.tileRectsIds.length ) ];
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
}
