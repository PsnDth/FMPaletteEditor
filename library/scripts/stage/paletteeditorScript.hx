// API Script for Palette Editor


// Vars

var ButtonUseType = {
  PRESSED: 0,
  HELD: 1,

  constToString: function(useType) {
    return switch (useType) {
      case ButtonUseType.PRESSED: "PRESSED";
      case ButtonUseType.HELD: "HELD";
      default: "INVALID_USE_TYPE";
    };
  },
};

var Util = {
  decodeStructId: function (struct_id) {
    return struct_id.namespace + "::" + struct_id.resourceId + "." + struct_id.contentId;
  },
  checkBits: function (num, mask) {
    return (num & mask) != 0x0;
  },
  waitUntil: function(condition, task) {
    var checker;
    checker = StageTimer.addCallback(function(){
      if (condition()) {
        task();
        StageTimer.removeCallback(checker);
      } 
    }, {persistent: true});
  },
  doSlowLoop: function(params, task_cb, done_cb) {
    var param_array = [for (p in params) p];
    var done_last = true;
    function do_next() {
      if (param_array.length == 0) return done_cb();
      Util.waitUntil(() -> done_last, function() {
        done_last = false;
        task_cb(param_array.shift(), function() { 
          done_last = true;
          do_next();
        });
      });
    }
    do_next();
  },
  findMaxCostume: function(obj: GameObject) {
    var guess = 1;
    do {
      obj.setCostumeIndex(guess);
      guess++;
    } while (obj.getCostumeIndex() >= guess-1);
    var max_costume = obj.getCostumeIndex();
    if (max_costume == 0) {
      Engine.log("Something went wrong while trying to find max costume ...", 0xB30202);
      return -1;
    }
    return max_costume;
  },
  onButtonsUsed: function(char:Character, buttonMask:Int, cb:Function, ?options:Dynamic) {
    // Valid option: 
    // - persistent: bool, default = false
    // - useType: ButtonsUseType, default = ButtonUseType.PRESSED
    // - includeInitial: bool, default = false
    if (options == null) {
      options = {}
    }
    if (options.persistent == null) options.persistent = false;
    if (options.useType == null) options.useType = ButtonUseType.PRESSED;
    if (options.includeInitial == null) options.includeInitial = false;
		// NOTE: Unlike engine eventlistener style functions, persistent here means it doesn't get cleared after firing once.
		var poll_for_press; // reference to remove the timer
		// Use closure to make sure these varibles persist ...
		(() -> {
			// Should not fire if pressed this frame.
			// TODO: This should probably be an option
      var getControls = function () {
        switch (options.useType) {
          case ButtonUseType.PRESSED: char.getPressedControls();
          case ButtonUseType.HELD: char.getHeldControls();
          default: char.getPressedControls();
        };
      };
			var seen_buttons = false;
      if (!options.includeInitial) 
        seen_buttons = Util.checkBits(getControls().buttons, buttonMask);
			poll_for_press = StageTimer.addCallback(() -> {
				if (Util.checkBits(getControls().buttons, buttonMask)) {
					if (!seen_buttons) {
						seen_buttons = true;
						cb();
						if (!options.persistent)
							StageTimer.removeCallback(poll_for_press);
					}
				} else {
					seen_buttons = false;
				}
			});
		})();
		// return callback so it can be removed manually
		return poll_for_press;
	},
 
};

// Tools for running callbacks on every frame! Call tick() every frame, and dependencies can hook into this call using this class
// Depends: match
var StageTimer = {
	// init: () -> match.addEventListener(MatchEvent.TICK_START, StageTimer._tick, {persistent: true}),
	init: () -> {},
	addCallback: (cb) -> StageTimer._callbacks.contains(cb) ? cb : StageTimer._callbacks[StageTimer._callbacks.push(cb) - 1],
	removeCallback: (cb) -> StageTimer._callbacks.remove(cb),
	/// Private
	_tick: () -> {
		for (cb in StageTimer._callbacks)
			cb();
	},
	_callbacks: [],
};

var PaletteResource = {
  palettes: null,
  init: function(palettes: StringMap) {
    if (palettes == null) {
      Engine.log("ERROR: Initializing Palette resource with palettes failed.", 0xD63939);
      return false;
    }
    PaletteResource.palettes = palettes;
    return true;
  },
  getPalette: function (id: String, costume_id: Int) {
    if (!PaletteResource.palettes.exists(id)) return null;
    if (!PaletteResource.palettes[id].exists(costume_id)) return null;
    return PaletteResource.palettes[id][costume_id];
  },
  getPaletteCostumes: function (id: String) {
    if (!PaletteResource.palettes.exists(id)) return [];
    return PaletteResource.palettes[id].keys();
  },
};

function initialize(){
	// Don't animate the stage itself (we'll pause on one version for hazards on, and another version for hazards off)
	self.pause();
  camera.setMode(3);
  var palette_gen = match.createCustomGameObject(self.getResource().getContent("custom_palettes"));
  if (palette_gen == null || palette_gen.exports.getPalettes == null) {
    Engine.log("ERROR: Couldn't find Palette resource.", 0xD63939);
    palettes = new StringMap();
    return;
  }
  if (!PaletteResource.init(palette_gen.exports.getPalettes())) return;
}

function applyCharacterPalette(char: Character) {
  var foe = char.getFoes()[0];
  handleCharacter(char, function() {
    // move foe directly in front of char
    char.faceRight();
    foe.setX(char.getX() + char.getEcbRightHipX());
    foe.setY(char.getY());
    if (!foe.inState(CState.STAND)) foe.toState(CState.STAND);
    handleAssist(char, function(){
      var metadata = char.getGameObjectStatsMetadata();
      if (metadata == null) {
        metadata = {};
        char.updateGameObjectStats({metadata: metadata});
      }
      metadata._pe_all_aplied = true;
    });
  });
}

// To use for (base-cast) things that need to be on-hit
var ATTACK_SEQUENCE = [
  "public::orcane.orcane" => [CState.JUMP_SQUAT, CState.AERIAL_FORWARD, CState.JUMP_MIDAIR, CState.SPECIAL_DOWN, CState.SPECIAL_NEUTRAL, CState.SPECIAL_UP],
  "public::fishbunjin.fishbunjin" => [CState.JUMP_SQUAT, CState.GRAB],
];

function handleCharacter(char: Character, done_cb: Function = null) {
  var id = Util.decodeStructId(char.getPlayerConfig().character);
  Engine.log("Handling " + id + " ...", 0x39D666);
  var costumes = PaletteResource.getPaletteCostumes(id);
  function applyCostume(costume_id, done_costume_cb) {
    var clean_up_handler = ensureCostume(char, id, costume_id);
    var curr_move = null;
    if (ATTACK_SEQUENCE.exists(id)) {
      var sequence  = ATTACK_SEQUENCE[id].copy();
      curr_move = sequence.shift();
      var prev_move = null;
      var sequence_handler;
      sequence_handler = char.addTimer(1, -1, function(){
        if (prev_move == null || !char.inState(prev_move)) {
          char.toState(curr_move);
          prev_move = curr_move;
          curr_move = sequence.shift();
        }
        if (curr_move == null) char.removeTimer(sequence_handler);
      }, {persistent: true});
    }
    Util.waitUntil( () -> curr_move == null && !char.inStateGroup(CStateGroup.ATTACK),  function(){
      for (proj in match.getProjectiles()) {
        proj.destroy();
      }
      clean_up_handler();
      done_costume_cb();
    });
  }
  done_cb = done_cb == null ? () -> {} : done_cb;
  Util.doSlowLoop(costumes, applyCostume, done_cb);
}

function handleAssist(char: Character, done_cb: Function = null) {
  // Spawn the assist as custom game object
  var id = Util.decodeStructId(char.getPlayerConfig().assist);
  Engine.log("Handling " + id + " ...", 0x39D666);
  var costumes = PaletteResource.getPaletteCostumes(id);
  function applyCostume(costume_id, done_costume_cb) {
    var assist = match.createCustomGameObject(id, char);
    var clean_up_handler = ensureCostume(assist, id, costume_id);
    assist.addEventListener(EntityEvent.COLLIDE_WALL, function(){
      assist.destroy();
    }, {persistent: true});
    Util.waitUntil(() -> assist.isDisposed(), function(){
      for (proj in match.getProjectiles()) {
        proj.destroy();
      }
      clean_up_handler();
      done_costume_cb();
    });
  };
  done_cb = done_cb == null ? () -> {} : done_cb;
  Util.doSlowLoop(costumes, applyCostume, done_cb);
}


destroy_handlers = [];
function ensureCostume(obj: GameObject, obj_id: String, costume_idx: Int) {
  var palette = PaletteResource.getPalette(obj_id, costume_idx);
  function revertOnDestroy(obj, old_costume) {
    var destroy_listener;
    destroy_listener = StageTimer.addCallback(function (?force_destroy) {
      if (obj.isDisposed() || force_destroy) {
        var shader = obj.getCostumeShader();
        for (color in old_costume.keys()) {
          shader.paletteMap[color] = old_costume[color];
        }
        obj.getCostumeShader().paletteMap = shader.paletteMap;
        StageTimer.removeCallback(destroy_listener);
        destroy_handlers.remove(destroy_listener);
      }
    });
    destroy_handlers.push(destroy_listener);
  }
  obj.setCostumeIndex(costume_idx);
  var asShader = null;
  var proj_watcher = null;
  if (costume_idx == -1) {
    asShader = function (entity: GameObject) {
      var shader = entity.getCostumeShader();
      if (shader == null || shader.paletteMap == null) return false;
      revertOnDestroy(entity, shader.paletteMap.copy());
      for (color in shader.paletteMap.keys()) {
        shader.paletteMap[color] = color;
      }
      entity.getCostumeShader().paletteMap = shader.paletteMap;
      return true;
    };
  } else if (palette != null) {
    asShader = function (entity: GameObject) {
      var shader = entity.getCostumeShader();
      if (shader == null || shader.paletteMap == null) return false;
      for (color in palette.keys()) {
        shader.paletteMap[color] = palette[color];
      }
      entity.getCostumeShader().paletteMap = shader.paletteMap;
      return true;
    };
  }
  if (asShader != null) {
    asShader(obj);
    var handled_projs = [];
    proj_watcher = obj.addTimer(1, -1, function(){
      for (p in match.getProjectiles()) {
        var projectile: Projectile = p;
        var owner = projectile.getRootOwner();
        if (owner == obj.getRootOwner() || owner == null) {
            if (!handled_projs.contains(projectile)) {
              if (!asShader(projectile)) continue;
              handled_projs.push(projectile);
            }
        } else {
          Engine.log("Found projectile with unexpected owner ...", 0xB30202);
        }
      }
    }, {persistent: true});
  }

  function stopHandler() {
    for (handler in destroy_handlers) {
      handler(true);
    }
    if (proj_watcher != null) obj.removeTimer(proj_watcher);

  }
  return stopHandler;
}

// TLE = Top Level Entity (i.e. char/assist)
var TLESelectionMode = {
  _enabled: true,
  _selection_cb: null,  
  _assist_boxes: [],
  _last_glow: null,
  
  _selected_char: 0,
  _assist_selected: false,

  init: function(?selection_cb) {
    TLESelectionMode._selection_cb = selection_cb;

    // Give glow to first character
    // Give assist box to all chars
    // set up selection handlers permanently and just enable/disable the view
    var chars = match.getCharacters();
    for (c in chars) {
			var char: Character = c;
      char.getDamageCounterContainer().visible = true;
      var assist_box = Container.create();
      assist_box.addChild(char.getDamageCounterAssistSprite());
      char.getDamageCounterContainer().addChild(assist_box);
      assist_box.x = 107;
      assist_box.y = 13;
      assist_box.alpha = 0.3;
      TLESelectionMode._assist_boxes.push(assist_box);
      if (TLESelectionMode._last_glow == null) {
        TLESelectionMode._last_glow = new GlowFilter();
        TLESelectionMode._last_glow.solid = false;
        TLESelectionMode._last_glow.color = 0x39D666;
        TLESelectionMode._last_glow.radius = 15;
        char.getDamageCounterContainer().addFilter(TLESelectionMode._last_glow);
      }
      // Don't allow CPUs to make selections, lol
      if (char.getPlayerConfig().cpu) return;

      Util.onButtonsUsed(char, Buttons.LEFT, function(){
        if (!TLESelectionMode._enabled) return;
        var selected_char = TLESelectionMode._selected_char;
        var assist_selected = TLESelectionMode._assist_selected;
        var updateSelection = TLESelectionMode.updateSelection;
        if (assist_selected) {
          updateSelection(selected_char, false);
        } else if (selected_char > 0) {
          updateSelection(selected_char - 1, true);
        }
      }, {persistent: true});  
      Util.onButtonsUsed(char, Buttons.RIGHT, function(){
        if (!TLESelectionMode._enabled) return;
        var selected_char = TLESelectionMode._selected_char;
        var assist_selected = TLESelectionMode._assist_selected;
        var updateSelection = TLESelectionMode.updateSelection;
        if (!assist_selected) {
          updateSelection(selected_char, true);
        } else if (selected_char < chars.length - 1) {
          updateSelection(selected_char + 1, false);
        }
      }, {persistent: true});
      Util.onButtonsUsed(char, Buttons.ACTION, function(){
        if (!TLESelectionMode._enabled) return;

        TLESelectionMode.disable();
        for (c in match.getCharacters()) {
          c.getDamageCounterContainer().visible = false;
        }
        if (TLESelectionMode._selection_cb != null) {
          TLESelectionMode._selection_cb(char, TLESelectionMode.getSelection());
        }
      }, {persistent: true});
    }
  },
  enter: function(?tle) {
    if (tle == null) {
      tle = {
        character: 0,
        assist: false
      };
    }
    TLESelectionMode.updateSelection(tle.character, tle.assist);
    for (char in match.getCharacters()) {
      char.getDamageCounterContainer().visible = true;
    }
    TLESelectionMode.enable();
    TLESelectionMode.showAssistBoxes();
  },
  updateSelection: function(new_char, should_select_assist) {
    var prev_char  = match.getCharacters()[TLESelectionMode._selected_char];
    var char  = match.getCharacters()[new_char];
    var assist_boxes = TLESelectionMode._assist_boxes;
    var prev_container: Container = TLESelectionMode._assist_selected ? assist_boxes[TLESelectionMode._selected_char] : prev_char.getDamageCounterContainer();
    var new_container: Container = should_select_assist ? assist_boxes[new_char] : char.getDamageCounterContainer();
    prev_container.removeFilter(TLESelectionMode._last_glow);
    TLESelectionMode._last_glow = new GlowFilter();
    TLESelectionMode._last_glow.solid = false;
    TLESelectionMode._last_glow.color = 0x39D666;
    TLESelectionMode._last_glow.radius = 15;
    new_container.addFilter(TLESelectionMode._last_glow);
    TLESelectionMode._selected_char = new_char;
    TLESelectionMode._assist_selected = should_select_assist;
  },
  getSelection: function() {
    return {
      character: TLESelectionMode._selected_char,
      assist: TLESelectionMode._assist_selected,
    };
  },
  enable: function() { TLESelectionMode._enabled = true; },
  disable: function() { TLESelectionMode._enabled = false; },
  hideAssistBoxes: function() {
    for (box in TLESelectionMode._assist_boxes) {
      box.visible = false;
    }
  },
  showAssistBoxes: function() {
    for (box in TLESelectionMode._assist_boxes) {
      box.visible = true;
    }
  },

};

var CostumeSelectionMode = {
  _selection_cb: null,
  _exit_cb: null,
  _handlers: [],
  _assist_obj: null,
  _enabled: false,
  _vfx: null,
  init: function(?selection_cb, ?exit_cb) {
    CostumeSelectionMode._selection_cb = selection_cb;
    CostumeSelectionMode._exit_cb = exit_cb;
  },
  enter: function(selector: Character, tle: Dynamic, ?start_idx: Int = 0) {

    for (c in match.getCharacters()) {
      var char: Character = c;
      char.pause();
      char.setVisible(false);
      char.toState(CState.UNINITIALIZED, "stand");
      char.updateAnimationStats({bodyStatus: BodyStatus.INTANGIBLE});
    }
  
    CostumeSelectionMode._enabled = true;
    var obj: GameObject = null;
    if (tle.assist) {
      var char = match.getCharacters()[tle.character];
      obj = match.createCustomGameObject(Util.decodeStructId(char.getPlayerConfig().assist), char);
      obj.setVisible(false);
      obj.pause();
      CostumeSelectionMode._assist_obj = obj;
    } else {
      obj = match.getCharacters()[tle.character];
      CostumeSelectionMode._assist_obj = null;
    }
    function respawnAssistIfNeeded() {
      if (CostumeSelectionMode._assist_obj == null) return;
      if (!CostumeSelectionMode._assist_obj.isDisposed()) return;
      var char = match.getCharacters()[tle.character];
      obj = match.createCustomGameObject(Util.decodeStructId(char.getPlayerConfig().assist), char);
      obj.setVisible(false);
      obj.pause();
      CostumeSelectionMode._assist_obj = obj;
    }
    function spawnCostumeVfx(costume_idx) {
      if (CostumeSelectionMode._vfx != null) CostumeSelectionMode._vfx.destroy();
      CostumeSelectionMode._vfx = match.createVfx(new VfxStats({
        spriteContent: obj.getResource().getContent("menu"),
        animation: tle.assist ? "assist_full" : "full",
        // TODO: Check if this is right
        x: (camera.getX() + camera.getViewportWidth() / 2) / camera.getZoomScaleX(),
        y: (camera.getY() + camera.getViewportHeight() / 2) / camera.getZoomScaleY(),
      }));

      // assume x/y
      var vfx_container: Container = CostumeSelectionMode._vfx.getViewRootContainer();
      // vfx_container.
      var yshift = -((vfx_container.height / 2) * camera.getZoomScaleY());
      yshift = tle.assist ? yshift : 0;
      var xshift = -((vfx_container.width / 2) * camera.getZoomScaleX());
      xshift = tle.assist ? xshift : 0;
      CostumeSelectionMode._vfx.move(xshift, yshift);
      CostumeSelectionMode._vfx.pause();
      camera.getForegroundContainer().addChild(vfx_container);
      if (costume_idx == -1) {
        obj.setCostumeIndex(0);
        return;
      }
      obj.setCostumeIndex(costume_idx);
      CostumeSelectionMode._vfx.addShader(obj.getCostumeShader());
    }
    var curr_costume_idx = start_idx;
    var MAX_COSTUME_IDX = Util.findMaxCostume(obj);
    spawnCostumeVfx(curr_costume_idx);
    // On left/right press go to next/previous costume
    var left_handler = Util.onButtonsUsed(selector, Buttons.LEFT, function(){
      respawnAssistIfNeeded();
      next_costume_idx = curr_costume_idx - 1;
      if (next_costume_idx < -1) next_costume_idx = MAX_COSTUME_IDX;
      curr_costume_idx = next_costume_idx;
      spawnCostumeVfx(curr_costume_idx);
    }, {persistent: true});
    var right_handler = Util.onButtonsUsed(selector, Buttons.RIGHT, function(){
      respawnAssistIfNeeded();
      next_costume_idx = curr_costume_idx + 1;
      if (next_costume_idx > MAX_COSTUME_IDX) next_costume_idx = 0;
      obj.setCostumeIndex(next_costume_idx);
      // Revert
      if (obj.getCostumeShader() == null) 
        obj.setCostumeIndex(next_costume_idx - 1);
      curr_costume_idx = obj.getCostumeIndex();
      spawnCostumeVfx(curr_costume_idx);
    }, {persistent: true});
    var select = Util.onButtonsUsed(selector, Buttons.ACTION, function(){
      CostumeSelectionMode._select(selector, tle, curr_costume_idx);
    }, {persistent: true});
    var exit = Util.onButtonsUsed(selector, Buttons.SPECIAL, function(){
      var held_count = 30;
      var held_timer;
      held_timer = selector.addTimer(1, 30, function(){
        if (!selector.getHeldControls().SPECIAL || !CostumeSelectionMode._enabled) {
          selector.removeTimer(held_timer);
          return;
        }
        held_count--;
        if (held_count == 0) {
          CostumeSelectionMode._exit(tle);
        }
      }, {persistent: true});
    }, {persistent: true});
    CostumeSelectionMode._handlers.push(left_handler);
    CostumeSelectionMode._handlers.push(right_handler);
    CostumeSelectionMode._handlers.push(select);
    CostumeSelectionMode._handlers.push(exit);
  },
  _clear_mode: function() {
    for (char in match.getCharacters()) {
      char.resume();
      char.setVisible(true);
      char.updateAnimationStats({bodyStatus: BodyStatus.NONE});
      char.toState(CState.STAND);
    }
    CostumeSelectionMode._vfx.destroy();
    CostumeSelectionMode._enabled = false;
    for (handler in CostumeSelectionMode._handlers) {
      StageTimer.removeCallback(handler);
    }
  },
  _exit: function(tle) {

    if (CostumeSelectionMode._exit_cb == null) return;
    CostumeSelectionMode._clear_mode();
    for (char in match.getCharacters()) {
      // Set back to chosen costume instead of selected one
      char.setCostumeIndex(char.getPlayerConfig().costume);
    }
    CostumeSelectionMode._exit_cb(tle);
  },
  _select: function(selector, tle, curr_costume_idx) {

    // Selectable:
    if (!CostumeSelectionMode._enabled) return;
    CostumeSelectionMode._clear_mode();
    if (CostumeSelectionMode._selection_cb != null) {
      CostumeSelectionMode._selection_cb(selector, tle, curr_costume_idx);
    }
  }
};

var PlaytestMode = {
  _exit_cb: null,

  _selector: null,
  _tle: null,
  _costume_id: null,

  _handlers: [],
  _costume_handler_clearer: null,

  init: function(?exit_cb) {
    PlaytestMode._exit_cb = exit_cb;
  },
  _applyCostume: function(obj, obj_id, costume) {
    PlaytestMode._costume_handler_clearer = ensureCostume(obj, obj_id, costume);
  },
  enter: function(selector, tle, costume_id) {
    PlaytestMode._selector = selector;
    PlaytestMode._tle = tle;
    PlaytestMode._costume_id = costume_id;
    // Disable all characters
    var other_chars = match.getCharacters().copy();
    var curr_char: Character = !tle.assist ? other_chars.splice(tle.character, 1)[0] : other_chars[tle.character];
    var char_id = Util.decodeStructId(curr_char.getPlayerConfig().character);

    if (!tle.assist) PlaytestMode._applyCostume(curr_char, char_id, costume_id);
    for (c in other_chars) {
      var char: Character = c;
      char.pause();
      char.setVisible(false);
      char.toState(CState.UNINITIALIZED, "stand");
      char.updateAnimationStats({bodyStatus: BodyStatus.INTANGIBLE});
      // var timer = char.applyGlobalBodyStatus(BodyStatus.INTANGIBLE, -1);
      char.updateAnimationStats({bodyStatus: BodyStatus.INTANGIBLE});
    }
    function handleButtonPress(was_assist) {
      if (was_assist) {
        if (tle.assist) {
          var assist_id = Util.decodeStructId(curr_char.getPlayerConfig().assist);
          var obj = match.createCustomGameObject(assist_id, curr_char);
          PlaytestMode._applyCostume(obj, assist_id, PlaytestMode._costume_id);
           return;
        }
        PlaytestMode._exit();
      } else {
        if (tle.assist) return PlaytestMode._exit();
        // not assist in regular mode, does regular actions
      }
    }
    PlaytestMode._handlers.push(Util.onButtonsUsed(selector, Buttons.ACTION, function(){
      handleButtonPress(true);
    }, {persistent: true}));
    var attack_buttons =  Buttons.GRAB | Buttons.ATTACK | Buttons.SHIELD |  Buttons.SPECIAL | Buttons.STRONG | Buttons.TILT;
    PlaytestMode._handlers.push(Util.onButtonsUsed(selector, attack_buttons, function(){
      handleButtonPress(false);
    }, {persistent: true}));
    if (curr_char.getPlayerConfig().cpu == false || curr_char.getPlayerConfig().level > 0 || tle.assist) return;
    PlaytestMode._handlers.push(StageTimer.addCallback(function(){
      // ignored unactionable states, or ones that shouldn't happen:
      // - crawl, ledge_*, attack stats
      var controls = selector.getPressedControls();
      var held_controls = selector.getHeldControls();
      function checkAirAttackOrJump() {
        var attack_any = controls.ATTACK || controls.TILT || controls.STRONG || controls.SPECIAL;
        // CStick takes priority
        var ang = controls.getAngle(true);
        var is_cstick = (ang != -1);
        if (ang == -1) ang = controls.getAngle();
        if (ang == -1) ang = held_controls.getAngle();
        if (!attack_any && !is_cstick)  {
          if (controls.JUMP_ANY) {
            // Always assume first jump since can't get number of jumps used via api ...
            curr_char.setYSpeed(curr_char.getCharacterStat("doubleJumpSpeeds")[0]);
            return CState.JUMP_MIDAIR;
          }
          if (controls.SHIELD || controls.SHIELD_AIR) return CState.AIRDASH_DELAY;
          return CState.UNINITIALIZED;
        }
        var is_special = (attack_any && controls.SPECIAL) || (!attack_any && controls.hasRightStickSpecialFlag());
        // var is_aerial =  !is_special;
        var next_state = is_special ? CState.SPECIAL_NEUTRAL : CState.AERIAL_NEUTRAL;
        if (ang == 90) {
          next_state = is_special ? CState.SPECIAL_UP : CState.AERIAL_UP;
        } else if (ang == 270) {
          next_state = is_special ? CState.SPECIAL_DOWN : CState.AERIAL_DOWN;
        } else if (curr_char.isFacingRight() ? ang == 0 : ang == 180) {
          next_state = is_special ? CState.SPECIAL_SIDE :  CState.AERIAL_FORWARD;
        } else if (curr_char.isFacingRight() ? ang == 180 : ang == 0) {
          if (is_special) curr_char.flip();
          next_state = is_special ? CState.SPECIAL_SIDE :  CState.AERIAL_BACK;
        }
        return next_state;
      }

      function checkGroundedAttackOrJump(is_run) {
        var attack_any = controls.ATTACK || controls.TILT || controls.STRONG || controls.SPECIAL;
        var is_pressed_ang = true;
        var is_held_ang = false;
        var is_cstick = false;
        var ang = controls.getAngle();
        if (ang == -1) {
          is_held_ang = true;
          is_pressed_ang = false;
          ang = held_controls.getAngle();
        }
        if (ang == -1) {
          is_held_ang = false;
          ang = controls.getAngle(true);
          is_cstick = (ang != -1);
        }

        if (!attack_any && !is_cstick) {
          if (controls.GRAB) return CState.GRAB;
          if (controls.JUMP_ANY) return CState.JUMP_SQUAT;
          if (controls.SHIELD) return CState.SHIELD_IN;
          if (controls.SHIELD_AIR) return CState.AIRDASH_DELAY;
          return CState.UNINITIALIZED;
        }
        
        var is_tilt_stick = !controls.hasRightStickAttackFlag() && !controls.hasRightStickSpecialFlag();
        var is_special = (attack_any && controls.SPECIAL) || (!attack_any && controls.hasRightStickSpecialFlag());
        var is_tilt = (attack_any && ((is_held_ang && controls.ATTACK) || controls.TILT)) || (!attack_any && is_tilt_stick);
        var is_strong = (attack_any && ((is_pressed_ang && controls.ATTACK) || controls.STRONG)) || (!attack_any && controls.hasRightStickAttackFlag());

        var next_state = is_special ? CState.SPECIAL_SIDE : (is_strong ? CState.STRONG_FORWARD_IN : CState.JAB);
        if (ang == 90) {
          next_state = is_special ? CState.SPECIAL_UP : (is_strong ? CState.STRONG_UP_IN : CState.TILT_UP);
        } else if (ang == 270) {
          next_state = is_special ? CState.SPECIAL_DOWN : (is_strong ? CState.STRONG_DOWN_IN : CState.TILT_DOWN);
        } else if (curr_char.isFacingRight() ? ang == 0 : ang == 180) {
          next_state = is_run ? CState.DASH_ATTACK : (is_special ? CState.SPECIAL_SIDE : (is_strong ? CState.STRONG_FORWARD_IN : CState.TILT_FORWARD));
        } else if (curr_char.isFacingRight() ? ang == 180 : ang == 0) {
          curr_char.flip();
          next_state = is_run ? CState.DASH_ATTACK : (is_special ? CState.SPECIAL_SIDE : (is_strong ? CState.STRONG_FORWARD_IN : CState.TILT_FORWARD));
        }
        return next_state;
      }

      function checkGroundMovement() {
        var is_pressed_ang = true;
        var is_held_ang = false;
        var ang = controls.getAngle();
        if (ang == -1) {
          is_held_ang = true;
          is_pressed_ang = false;
          ang = held_controls.getAngle();
        }
        var is_back = curr_char.isFacingRight() ? ang == 180 : ang == 0;
        if (ang == -1) return CState.UNINITIALIZED;
        
        if (is_back) {
          curr_char.flip();
          is_pressed_ang = true;
          is_held_ang = false;
        }
        if (ang == 270) {
          if (!curr_char.inState(CState.UNINITIALIZED)) {
            return CState.CROUCH_IN;
          }
        }
        var in_move_state = curr_char.inStateGroup(CStateGroup.RUN) || curr_char.inStateGroup(CStateGroup.WALK) || curr_char.inState(CState.UNINITIALIZED) || curr_char.inStateGroup(CStateGroup.DASH);
        var trying_to_move = held_controls.LEFT ||  held_controls.RIGHT || controls.LEFT || controls.RIGHT;
        if (trying_to_move && (!in_move_state || is_back)) {
          if (held_controls.DASH || controls.DASH) {
            return CState.DASH;
          } else {
            return CState.WALK_IN;
          }
        }
        return CState.UNINITIALIZED;
      }
      function handleGroundState(is_run) {
        var res = checkGroundedAttackOrJump(is_run);
        if (res != CState.UNINITIALIZED) return res;
        return checkGroundMovement();
      }
      
      // Engine.log("init_state={" + CState.constToString(curr_char.getState()) + ", " + curr_char.getAnimation() + ", f" + curr_char.getCurrentFrame() + "/" + curr_char.getTotalFrames() + "} pressed=" + controls+ " held=" + held_controls + ";");

      var next_state = switch (curr_char.getState()) {
        case CState.STAND: handleGroundState(false);
        case CState.STAND_TURN: handleGroundState(false);
        case CState.WALK_IN:  handleGroundState(false);
        case CState.WALK_LOOP:  handleGroundState(false);
        case CState.WALK_OUT:  handleGroundState(false);
        case CState.DASH: handleGroundState(true);
        case CState.DASH_PIVOT: handleGroundState(false);
        case CState.RUN: handleGroundState(true);
        case CState.RUN_TURN: handleGroundState(true);
        case CState.SKID: handleGroundState(false);
        // case CState.JUMP_SQUAT: {};
        case CState.JUMP_IN: checkAirAttackOrJump();
        case CState.JUMP_LOOP: checkAirAttackOrJump();
        case CState.JUMP_OUT: checkAirAttackOrJump();
        case CState.JUMP_MIDAIR: checkAirAttackOrJump();
        case CState.FALL: checkAirAttackOrJump();
        case CState.CROUCH_IN: checkGroundedAttackOrJump(false);
        case CState.CROUCH_LOOP: checkGroundedAttackOrJump(false);
        case CState.CROUCH_OUT: checkGroundedAttackOrJump(false);
        // case CState.PARRY_SUCCESS: {};
        case CState.TUMBLE: checkAirAttackOrJump();
        case CState.CRASH_LOOP: {
          var next_state = CState.UNINITIALIZED;
          if (controls.UP) {
            next_state = CState.CRASH_GET_UP;
          } else if (controls.ATTACK || controls.SPECIAL) {
            next_state = CState.CRASH_ATTACK;
          } else if (controls.LEFT || controls.RIGHT) {
            next_state = CState.CRASH_ROLL;
          }
          next_state;
        };
        case CState.GRAB_HOLD: {
          var pressedLeft = controls.LEFT || controls.RIGHT_STICK_LEFT;
          var pressedRight = controls.RIGHT || controls.RIGHT_STICK_RIGHT;
          var pressedForward = (pressedLeft && curr_char.isFacingLeft()) || (pressedRight && curr_char.isFacingRight);
          var pressedBack = (pressedRight && curr_char.isFacingLeft()) || (pressedLeft && curr_char.isFacingRight);
          var next_state = CState.UNINITIALIZED;
          if (controls.UP | controls.RIGHT_STICK_UP) {
            next_state = CState.THROW_UP;
          } else if (controls.DOWN | controls.RIGHT_STICK_DOWN) {
            next_state = CState.THROW_DOWN;
          } else if (pressedForward) {
            next_state = CState.THROW_FORWARD;
          } else if (pressedBack) {
            next_state = CState.THROW_BACK;
          }
          next_state;
        };
        case CState.UNINITIALIZED: {
          var next_state = CState.UNINITIALIZED;
          /// Handle WAlk
          var curr_anim = curr_char.getAnimation();
          var in_walk = curr_anim.substring(0, 4) == "walk";
          var in_crouch = curr_anim.substring(0, 6) == "crouch";
          if (in_walk || in_crouch) {
            next_state = handleGroundState(false);
          }
          if (curr_anim == "walk_in" && curr_char.finalFramePlayed()) {
            curr_char.playAnimation("walk_loop");
          }
          if (curr_anim == "walk_loop") {
            var should_continue_looping = (curr_char.isFacingLeft() == held_controls.LEFT) && (curr_char.isFacingRight() == held_controls.RIGHT);
            if (!should_continue_looping) {
              curr_char.playAnimation("walk_out");
            } else {
              var max_speed = curr_char.getCharacterStat("walkSpeedCap");
              var accel = curr_char.getCharacterStat("walkSpeedAcceleration");
              var curr_speed = curr_char.getXSpeed();
              curr_char.setXSpeed(Math.min(max_speed, curr_speed + accel));
            }
          }
          if (curr_anim == "walk_out" && curr_char.finalFramePlayed()) {
            next_state = CState.STAND;
          }
          if (curr_anim == "crouch_in" && curr_char.finalFramePlayed()) {
            curr_char.playAnimation("crouch_loop");
          }
          else if (curr_anim == "crouch_loop" && !held_controls.DOWN) {
              curr_char.playAnimation("crouch_out");
          }
          if (curr_anim == "crouch_out" && curr_char.finalFramePlayed()) {
            next_state = CState.STAND;
          }
          if (curr_anim == "shield_in" && curr_char.finalFramePlayed()) {
            curr_char.playAnimation("shield_loop");
          }
          if (curr_anim == "shield_loop") {
            if (!held_controls.SHIELD) curr_char.playAnimation("shield_out");
          }
          if (curr_anim == "shield_out" && curr_char.finalFramePlayed()) {
            next_state = CState.STAND;
          }
          // Enging.log(curr_char.)
          next_state;
        };
        default: {
          CState.UNINITIALIZED;
        }
      };
      var invalid_states = [CState.UNINITIALIZED, curr_char.getState()];
      var reentrant_states = [CState.JUMP_MIDAIR];
      if (!invalid_states.contains(next_state) || reentrant_states.contains(next_state)) {
        var anim = null;
        if (next_state == CState.WALK_IN) {
          next_state = CState.UNINITIALIZED;
          anim = "walk_in";
          curr_char.setXSpeed(curr_char.getCharacterStat("walkSpeedInitial"));
        }
        if (next_state == CState.CROUCH_IN) {
          next_state = CState.UNINITIALIZED;
          // crouch_in is weird, it forces crouch_out state if down is not pressed it seems. Baked into the anim, not even state. So jump straight to loop
          anim = "crouch_loop"; 
        }
        if (next_state == CState.SHIELD_IN) {
          next_state = CState.UNINITIALIZED;
          anim = "shield_loop";
        }
        curr_char.toState(next_state, anim);
      }
    }));
  },
  _exit: function() {
    if (PlaytestMode._costume_handler_clearer != null) PlaytestMode._costume_handler_clearer();
    for (handler in PlaytestMode._handlers) {
      StageTimer.removeCallback(handler);
    }
    
    var selector = PlaytestMode._selector;
    var tle = PlaytestMode._tle;
    var costume_id = PlaytestMode._costume_id;
    for (c in match.getCharacters()) {
      var char: Character = c;
      char.updateAnimationStats({bodyStatus: BodyStatus.NONE});
      char.setVisible(true);
      char.resume();
      char.toState(CState.STAND);
    }
    if (PlaytestMode._exit_cb != null) PlaytestMode._exit_cb(selector, tle, costume_id);
  }
};

var AssistDisabler = {
  _enabled: false,
  init: function() {
    StageTimer.addCallback(function(){
      if (AssistDisabler._enabled) {
        for (char in match.getCharacters()) {
          char.setAssistCharge(0);
        }
      }
    });
  },
  allowAssist: function(should_allow) { AssistDisabler._enabled = !should_allow; },
}

function hideEverything() {
  var i = 0;
  TLESelectionMode.hideAssistBoxes();
  for (char in match.getCharacters()) {
    char.setVisible(false);
    char.pause();
    i++;
  }
}

var done = false;
function update(){
	if (!done) {
    var prev_char: Character = null;
    function waitUntilPrevCharApplied(task) {
      // need to capture the current value otherwise will check the wrong thing
      var char_to_check: Character = prev_char;
      Util.waitUntil(function(){
          var metadata = char_to_check.getGameObjectStatsMetadata();
          return (metadata != null && metadata._pe_all_aplied == true);
        }, task);
    };
    for (c in match.getCharacters()) {
			var char: Character = c;
      if (prev_char != null) {
        waitUntilPrevCharApplied(() -> applyCharacterPalette(char));
      } else {
        applyCharacterPalette(char);
      }
      prev_char = char;
    }
    waitUntilPrevCharApplied(function() {

      var should_kill_everyone = true;
      // If training mode, don't bother, it won't work
      for (rule in match.getMatchSettingsConfig().matchRules) {
        if (Util.decodeStructId(rule) == "global::vsmode.infinitelives") {
          should_kill_everyone = false;
          break;
        }
      }
      // If any player is holding the action button should skip
      for (char in match.getCharacters()) {
        char.setCostumeIndex(char.getPlayerConfig().costume);
        if (char.getHeldControls().ACTION) {
          should_kill_everyone = false;
        }
      }
      if (should_kill_everyone) {
        for (char in match.getCharacters()) {
          char.setLives(1);
          char.setX(self.getDeathBounds().getRectangle().right + self.getDeathBounds().getX() + 20);
        }
      }

      TLESelectionMode.init(CostumeSelectionMode.enter);
      CostumeSelectionMode.init(PlaytestMode.enter, TLESelectionMode.enter);
      PlaytestMode.init(CostumeSelectionMode.enter);
      TLESelectionMode.enter();
      AssistDisabler.allowAssist(false); // Assist should be managed by individual modes, should never need/want engine functionality
    });
		done = true;
	}
  StageTimer._tick();
}

function onTeardown() {
  for (handler in destroy_handlers) {
    handler(true);
  }
}
