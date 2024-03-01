package ldtk;

class Layer_IntGrid_AutoLayer extends ldtk.Layer_IntGrid {
	/**
		A single array containing all AutoLayer tiles informations, in "render" order (ie. 1st is behind, last is on top)
	**/
	public var autoTiles : Array<ldtk.Layer_AutoLayer.AutoTile>;


	/** Getter to layer untyped Tileset instance. The typed value is created in macro. **/
	public var untypedTileset(get,never) : ldtk.Tileset;
		inline function get_untypedTileset() return untypedProject._untypedTilesets.get(tilesetUid);

	/** Tileset UID **/
	public var tilesetUid : Int;


	public function new(p,json) {
		super(p,json);

		autoTiles = [];
		tilesetUid = json.__tilesetDefUid;

		for(jsonAutoTile in json.autoLayerTiles)
			autoTiles.push({
				tileId: jsonAutoTile.t,
				flips: jsonAutoTile.f,
				alpha: jsonAutoTile.a,
				renderX: jsonAutoTile.px[0],
				renderY: jsonAutoTile.px[1],
				ruleId: jsonAutoTile.d[0],
				coordId: jsonAutoTile.d[1],
			});
	}

    public override function applyAllRules() {
        super.applyAllRules();
		
        var arr:Array<ldtk.Layer_AutoLayer.AutoTile> = [];

        if( autoTilesCache!=null ) {
            var td = getTilesetDef();
            iterateActiveRulesInDisplayOrder( this, (r)->{
                if( autoTilesCache.exists( r.uid ) ) {
                    for( allTiles in autoTilesCache.get( r.uid ).keyValueIterator() )
                    for( tileInfos in allTiles.value ) {
                        var at = {
                            tileId: tileInfos.tid,
                            flips: tileInfos.flips,
                            alpha: r.alpha,
                            renderX: tileInfos.x,
                            renderY: tileInfos.y,
                            ruleId: r.uid,
                            coordId: allTiles.key,
                        };
                        arr.push(at);
                    }
                }
            });
        }

        autoTiles = arr;
        
	}

    override function applyAllRulesAt(cx:Int, cy:Int, wid:Int, hei:Int) {
        super.applyAllRulesAt(cx, cy, wid, hei);

        var arr:Array<ldtk.Layer_AutoLayer.AutoTile> = [];

        //TODO would be better to only replace the update autotiles not all of them it's slow
        if( autoTilesCache!=null ) {
            var td = getTilesetDef();
            iterateActiveRulesInDisplayOrder( this, (r)->{
                if( autoTilesCache.exists( r.uid ) ) {
                    for( allTiles in autoTilesCache.get( r.uid ).keyValueIterator() )
                    for( tileInfos in allTiles.value ) {
                        var at = {
                            tileId: tileInfos.tid,
                            flips: tileInfos.flips,
                            alpha: r.alpha,
                            renderX: tileInfos.x,
                            renderY: tileInfos.y,
                            ruleId: r.uid,
                            coordId: allTiles.key,
                        };
                        arr.push(at);
                    }
                }
            });
        }
        
        autoTiles = arr;
    }



	#if !macro

		#if heaps
		/**
			Render layer to a `h2d.TileGroup`. If `target` isn't provided, a new h2d.TileGroup is created. If `target` is provided, it **must** have the same tile source as the layer tileset!
		**/
		public inline function render(?target:h2d.TileGroup) : h2d.TileGroup {
			if( target==null )
				target = new h2d.TileGroup( untypedTileset.getAtlasTile() );

			/*if(renderTarget != null)
				target = renderTarget;*/

			for( autoTile in autoTiles )
				target.addAlpha(
					autoTile.renderX + pxTotalOffsetX,
					autoTile.renderY + pxTotalOffsetY,
					autoTile.alpha,
					untypedTileset.getAutoLayerTile(autoTile)
				);

			/*if(renderTarget == null)
				renderTarget = target;*/

			return target;
		}
		#end


		#if flixel
		/**
			Render layer to a `FlxGroup`. If `target` isn't provided, a new one is created.
		**/
		public function render(?target:flixel.group.FlxSpriteGroup) : flixel.group.FlxSpriteGroup {
			if( target==null ) {
				target = new flixel.group.FlxSpriteGroup();
				target.active = false;
			}


			for( autoTile in autoTiles ) {
				var s = new flixel.FlxSprite(autoTile.renderX, autoTile.renderY);
				s.flipX = autoTile.flips & 1 != 0;
				s.flipY = autoTile.flips & 2 != 0;
				s.frame = untypedTileset.getFrame(autoTile.tileId);
				target.add(s);
			}

			return target;
		}
		#end

	#end
}
