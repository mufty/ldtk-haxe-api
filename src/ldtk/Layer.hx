package ldtk;

import dn.M;
import ldtk.Json;

class Layer {

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

	public var autoTilesCache :
		Null< Map<Int, // RuleUID
			Map<Int, // CoordID
				// WARNING: x/y don't contain layerDef.pxOffsetX/Y (to avoid the need of a global update when changing these values). They are added in the JSON though.
				Array<{ x:Int, y:Int, flips:Int, srcX:Int, srcY:Int, tid:Int, a:Float }>
			>
		> > = null;

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
	}

	/** Print class debug info **/
	@:keep public function toString() {
		return 'ldtk.Layer[#$identifier, type=$type]';
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
		var right = dn.M.imin( cWid-1, cx + wid);
		var top = dn.M.imax( 0, cy - hei );
		var bottom = dn.M.imin( cHei-1, cy + hei);


		// Apply rules
        if(defJson.autoSourceLayerDefUid!=null)
            trace("aa");
		var source = defJson.autoSourceLayerDefUid!=null ? getLayerInstance(defJson.autoSourceLayerDefUid) : this;
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

    function getLayerInstance(uid:Int){
		var res = null;
        for(ul in Level.ME.allUntypedLayers){
            if(uid == ul.json.layerDefUid){
                res = ul;
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

	public function iterateActiveRulesInEvalOrder( li:Layer, cbEachRule:(r:AutoRuleDef)->Void ) {
		for(rg in defJson.autoRuleGroups)
			if( li.isRuleGroupActiveHere(rg) )
				for(r in rg.rules)
					if( r.active)
						cbEachRule(r);
	}

	function applyAutoLayerRuleAt(source:Layer, r:AutoRuleDef, cx:Int, cy:Int) : Bool {
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

	inline function addRuleTilesAt(r:AutoRuleDef, cx:Int, cy:Int, flips:Int) {
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

	public inline function getIntGrid(cx:Int, cy:Int) : Int {
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
