package ldtk;

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
}
