// 道路：先在格子上走一条正交路线，再画成等宽走廊和稍宽的房间。
// 小屋：在一栋房子的剖面里排房间、门、楼梯、窗台和屋后的树根。
// 高塔：主路不断爬高，途中分出纵向支路，有的绕回去，外形跟着种子错开。
// 没接上的形状之间留出空隙，避免叠成一团。
(function (root) {
	var PITCH = 7;
	var STROKE = 3;
	var OFF = 2;
	var GAP = 2;
	var COLS = 46;
	var ROWS = 28;

	function mulberry32(seed) {
		var a = seed >>> 0;
		return function () {
			a = (a + 0x6d2b79f5) | 0;
			var t = Math.imul(a ^ (a >>> 15), 1 | a);
			t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
			return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
		};
	}

	function opposite(dir) {
		return { left: "right", right: "left", up: "down", down: "up" }[dir];
	}

	function overlaps(a, b) {
		return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
	}

	function tooClose(a, b) {
		return a.x < b.x + b.w + GAP && a.x + a.w + GAP > b.x && a.y < b.y + b.h + GAP && a.y + a.h + GAP > b.y;
	}

	function sharesDoor(a, b) {
		var overlap;
		if (a.x + a.w === b.x || b.x + b.w === a.x) {
			overlap = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
			return overlap >= STROKE;
		}
		if (a.y + a.h === b.y || b.y + b.h === a.y) {
			overlap = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
			return overlap >= STROKE;
		}
		return false;
	}

	function keyOf(x, y) {
		return x + "," + y;
	}

	function inGrid(x, y) {
		return x >= 1 && y >= 1 && x < COLS - 1 && y < ROWS - 1;
	}

	function step(x, y, dir) {
		if (dir === "right") return { x: x + 1, y: y };
		if (dir === "left") return { x: x - 1, y: y };
		if (dir === "down") return { x: x, y: y + 1 };
		return { x: x, y: y - 1 };
	}

	function shuffle(list, rng) {
		var i;
		for (i = list.length - 1; i > 0; i--) {
			var swap = Math.floor(rng() * (i + 1));
			var tmp = list[i];
			list[i] = list[swap];
			list[swap] = tmp;
		}
		return list;
	}

	function uniqueDirs(list) {
		var result = [];
		var i;
		for (i = 0; i < list.length; i++) {
			if (result.indexOf(list[i]) < 0) result.push(list[i]);
		}
		return result;
	}

	function link(a, b, dir) {
		a.links.push({ dir: dir, id: b.id });
		b.links.push({ dir: opposite(dir), id: a.id });
	}

	function unlink(node, id) {
		node.links = node.links.filter(function (item) {
			return item.id !== id;
		});
	}

	function paintRun(cells) {
		var a = cells[0];
		var b = cells[cells.length - 1];
		var x0 = Math.min(a.x, b.x);
		var x1 = Math.max(a.x, b.x);
		var y0 = Math.min(a.y, b.y);
		var y1 = Math.max(a.y, b.y);
		if (a.y === b.y) {
			return { x: x0 * PITCH + OFF, y: a.y * PITCH + OFF, w: (x1 - x0) * PITCH + STROKE, h: STROKE };
		}
		return { x: a.x * PITCH + OFF, y: y0 * PITCH + OFF, w: STROKE, h: (y1 - y0) * PITCH + STROKE };
	}

	function joinToward(rect, other, axis) {
		var overlapX = Math.min(rect.x + rect.w, other.x + other.w) - Math.max(rect.x, other.x);
		var overlapY = Math.min(rect.y + rect.h, other.y + other.h) - Math.max(rect.y, other.y);
		var options = [];
		if (axis !== "v" && other.x >= rect.x + rect.w && overlapY >= STROKE) options.push({ gap: other.x - (rect.x + rect.w), dir: "right" });
		if (axis !== "v" && rect.x >= other.x + other.w && overlapY >= STROKE) options.push({ gap: rect.x - (other.x + other.w), dir: "left" });
		if (axis !== "h" && other.y >= rect.y + rect.h && overlapX >= STROKE) options.push({ gap: other.y - (rect.y + rect.h), dir: "down" });
		if (axis !== "h" && rect.y >= other.y + other.h && overlapX >= STROKE) options.push({ gap: rect.y - (other.y + other.h), dir: "up" });
		if (!options.length) return "";
		options.sort(function (a, b) {
			return a.gap - b.gap;
		});
		var best = options[0];
		if (best.dir === "right") rect.w += best.gap;
		else if (best.dir === "left") {
			rect.x -= best.gap;
			rect.w += best.gap;
		} else if (best.dir === "down") rect.h += best.gap;
		else {
			rect.y -= best.gap;
			rect.h += best.gap;
		}
		return best.dir;
	}

	function acceptable(piece, anchors, existing) {
		var i;
		if (piece.x < 1 || piece.y < 1 || piece.x + piece.w > COLS * PITCH - 1 || piece.y + piece.h > ROWS * PITCH - 1) return false;
		for (i = 0; i < anchors.length; i++) {
			if (overlaps(piece, anchors[i]) || !sharesDoor(piece, anchors[i])) return false;
		}
		for (i = 0; i < existing.length; i++) {
			if (anchors.indexOf(existing[i]) >= 0) continue;
			if (tooClose(piece, existing[i])) return false;
		}
		return true;
	}

	function splitRuns(cells) {
		var runs = [];
		var current = [cells[0]];
		var i;
		for (i = 1; i < cells.length; i++) {
			var prev = cells[i - 1];
			var before = current.length >= 2 ? current[current.length - 2] : null;
			var straight = before && cells[i].x - prev.x === prev.x - before.x && cells[i].y - prev.y === prev.y - before.y;
			if (straight) current.push(cells[i]);
			else {
				runs.push(current);
				current = [cells[i]];
			}
		}
		runs.push(current);
		return runs;
	}

	function createWorld() {
		return { chunks: [], occupied: {}, kind: {}, owner: {}, nextId: 1 };
	}

	function snapshot(world) {
		return {
			n: world.chunks.length,
			occupied: Object.assign({}, world.occupied),
			kind: Object.assign({}, world.kind),
			owner: Object.assign({}, world.owner),
			nextId: world.nextId,
			links: world.chunks.map(function (chunk) {
				return chunk.links.map(function (item) {
					return { dir: item.dir, id: item.id };
				});
			}),
		};
	}

	function restore(world, shot) {
		var i;
		world.chunks.length = shot.n;
		for (i = 0; i < world.chunks.length; i++) world.chunks[i].links = shot.links[i];
		world.occupied = shot.occupied;
		world.kind = shot.kind;
		world.owner = shot.owner;
		world.nextId = shot.nextId;
	}

	function markCell(world, x, y, kind, chunk) {
		var key = keyOf(x, y);
		world.occupied[key] = true;
		world.kind[key] = kind;
		world.owner[key] = chunk;
	}

	function roomTouchesRoom(world, gx, gy, cw, ch) {
		var y;
		var x;
		for (y = gy - 1; y <= gy + ch; y++) {
			for (x = gx - 1; x <= gx + cw; x++) {
				if (x >= gx && x < gx + cw && y >= gy && y < gy + ch) continue;
				if (world.kind[keyOf(x, y)] === "room") return true;
			}
		}
		return false;
	}

	function canRoom(world, gx, gy, cw, ch) {
		var y;
		var x;
		if (roomTouchesRoom(world, gx, gy, cw, ch)) return false;
		for (y = gy; y < gy + ch; y++) {
			for (x = gx; x < gx + cw; x++) {
				if (!inGrid(x, y) || world.occupied[keyOf(x, y)]) return false;
			}
		}
		return true;
	}

	function attachRoom(world, gx, gy, cw, ch, anchor) {
		var rect = { x: gx * PITCH, y: gy * PITCH, w: cw * PITCH, h: ch * PITCH, role: "room", links: [], gx: gx, gy: gy, cw: cw, ch: ch };
		var dir = "";
		if (anchor) {
			dir = joinToward(rect, anchor, "any");
			if (!dir) return null;
			if (!acceptable(rect, [anchor], world.chunks)) return null;
		} else if (!acceptable(rect, [], world.chunks)) return null;
		rect.id = world.nextId;
		world.nextId += 1;
		world.chunks.push(rect);
		if (anchor) link(anchor, rect, opposite(dir));
		var y;
		var x;
		for (y = gy; y < gy + ch; y++) {
			for (x = gx; x < gx + cw; x++) markCell(world, x, y, "room", rect);
		}
		return rect;
	}

	function roomSizes(verticality) {
		var sizes = [
			[2, 1],
			[3, 1],
			[2, 1],
			[4, 1],
			[2, 2],
		];
		if (verticality >= 0.35) sizes.push([1, 2], [1, 3], [2, 2]);
		return sizes;
	}

	function roomOrigin(door, dir, cw, ch) {
		if (dir === "right") return { x: door.x + 1, y: door.y - Math.floor((ch - 1) / 2) };
		if (dir === "left") return { x: door.x - cw, y: door.y - Math.floor((ch - 1) / 2) };
		if (dir === "down") return { x: door.x - Math.floor((cw - 1) / 2), y: door.y + 1 };
		return { x: door.x - Math.floor((cw - 1) / 2), y: door.y - ch };
	}

	function tryRoom(world, door, dir, anchor, rng, verticality) {
		var sizes = shuffle(roomSizes(verticality), rng);
		var i;
		for (i = 0; i < sizes.length; i++) {
			var origin = roomOrigin(door, dir, sizes[i][0], sizes[i][1]);
			if (!canRoom(world, origin.x, origin.y, sizes[i][0], sizes[i][1])) continue;
			var room = attachRoom(world, origin.x, origin.y, sizes[i][0], sizes[i][1], anchor);
			if (room) return room;
		}
		return null;
	}

	function dirChoices(current, straightCount, rng, verticality) {
		var list = [];
		var vertical = current === "up" || current === "down";
		var maxStraight = vertical ? 2 : 4;
		if (straightCount < maxStraight && rng() < (vertical ? 0.2 + verticality * 0.35 : 0.7 - verticality * 0.15)) list.push(current);
		if (vertical) {
			list.push("right");
			if (rng() < 0.4) list.push("left");
		} else if (rng() < 0.18 + verticality * 0.62) {
			list.push(rng() < 0.5 ? "up" : "down");
		}
		list.push("right", "up", "down", "left");
		return uniqueDirs(list);
	}

	function walk(world, start, dir, length, rng, verticality) {
		if (!inGrid(start.x, start.y) || world.occupied[keyOf(start.x, start.y)]) return [];
		var cells = [{ x: start.x, y: start.y }];
		var local = {};
		local[keyOf(start.x, start.y)] = true;
		var pos = { x: start.x, y: start.y };
		var facing = dir;
		var straightCount = 0;
		var i;
		for (i = 1; i < length; i++) {
			var choices = dirChoices(facing, straightCount, rng, verticality);
			var moved = false;
			var c;
			for (c = 0; c < choices.length; c++) {
				var next = step(pos.x, pos.y, choices[c]);
				var key = keyOf(next.x, next.y);
				if (!inGrid(next.x, next.y) || world.occupied[key] || local[key]) continue;
				local[key] = true;
				cells.push(next);
				straightCount = choices[c] === facing ? straightCount + 1 : 0;
				pos = next;
				facing = choices[c];
				moved = true;
				break;
			}
			if (!moved) break;
		}
		return cells;
	}

	function commitPath(world, cells, startChunk, endChunk) {
		if (!cells.length) return null;
		var runs = splitRuns(cells);
		var made = [];
		var existing = world.chunks.slice();
		var r;
		for (r = 0; r < runs.length; r++) {
			var rect = paintRun(runs[r]);
			var axis = runs[r].length === 1 ? "any" : runs[r][0].y === runs[r][runs[r].length - 1].y ? "h" : "v";
			rect.role = "corridor";
			rect.links = [];
			var anchors = [];
			var dirs = [];
			if (r === 0) {
				var dirStart = joinToward(rect, startChunk, axis);
				if (!dirStart) return null;
				anchors.push(startChunk);
				dirs.push(opposite(dirStart));
			} else {
				var dirPrev = joinToward(rect, made[r - 1], axis);
				if (!dirPrev) return null;
				anchors.push(made[r - 1]);
				dirs.push(opposite(dirPrev));
			}
			if (endChunk && r === runs.length - 1) {
				var dirEnd = joinToward(rect, endChunk, axis);
				if (!dirEnd) return null;
				anchors.push(endChunk);
				dirs.push(opposite(dirEnd));
			}
			if (Math.min(rect.w, rect.h) !== STROKE) return null;
			if (!acceptable(rect, anchors, existing)) return null;
			rect.id = world.nextId;
			world.nextId += 1;
			rect.anchors = anchors;
			rect.anchorDirs = dirs;
			made.push(rect);
			existing.push(rect);
		}
		var i;
		for (i = 0; i < made.length; i++) {
			var piece = made[i];
			world.chunks.push(piece);
			var a;
			for (a = 0; a < piece.anchors.length; a++) link(piece.anchors[a], piece, piece.anchorDirs[a]);
			delete piece.anchors;
			delete piece.anchorDirs;
		}
		for (i = 0; i < cells.length; i++) markCell(world, cells[i].x, cells[i].y, "corridor", made[0]);
		for (r = 0; r < runs.length; r++) {
			for (i = 0; i < runs[r].length; i++) world.owner[keyOf(runs[r][i].x, runs[r][i].y)] = made[r];
		}
		return made[made.length - 1];
	}

	function exitsOf(world, room) {
		var midX = room.gx + Math.floor((room.cw - 1) / 2);
		var midY = room.gy + Math.floor((room.ch - 1) / 2);
		var list = [
			{ x: room.gx + room.cw, y: midY, dir: "right" },
			{ x: room.gx - 1, y: midY, dir: "left" },
			{ x: midX, y: room.gy + room.ch, dir: "down" },
			{ x: midX, y: room.gy - 1, dir: "up" },
		];
		return list.filter(function (exit) {
			return inGrid(exit.x, exit.y) && !world.occupied[keyOf(exit.x, exit.y)];
		});
	}

	function orderExits(exits, rng, verticality) {
		var weight = { right: 8, left: 2, up: 1 + verticality * 5, down: 1 + verticality * 5 };
		var ranked = exits.slice();
		var i;
		for (i = 0; i < ranked.length; i++) ranked[i].rank = weight[ranked[i].dir] + rng();
		ranked.sort(function (a, b) {
			return b.rank - a.rank;
		});
		return ranked;
	}

	function extendFrom(world, room, rng, verticality, minLen, maxLen) {
		var exits = orderExits(exitsOf(world, room), rng, verticality);
		var i;
		for (i = 0; i < exits.length; i++) {
			var verticalExit = exits[i].dir === "up" || exits[i].dir === "down";
			var cap = verticalExit ? Math.min(maxLen, 3) : maxLen;
			var length = minLen + Math.floor(rng() * (cap - minLen + 1));
			var cells = walk(world, exits[i], exits[i].dir, length, rng, verticality);
			if (cells.length < 2) continue;
			var shot = snapshot(world);
			var tail = commitPath(world, cells, room, null);
			if (!tail) {
				restore(world, shot);
				continue;
			}
			var door = cells[cells.length - 1];
			var next = tryRoom(world, door, tailDir(cells), tail, rng, verticality);
			if (!next) {
				restore(world, shot);
				continue;
			}
			return next;
		}
		return null;
	}

	function tailDir(cells) {
		var last = cells[cells.length - 1];
		var prev = cells[cells.length - 2];
		if (last.x > prev.x) return "right";
		if (last.x < prev.x) return "left";
		if (last.y > prev.y) return "down";
		return "up";
	}

	function corridorCells(world) {
		var list = [];
		var key;
		for (key in world.kind) {
			if (world.kind[key] === "corridor") {
				var parts = key.split(",");
				list.push({ x: Number(parts[0]), y: Number(parts[1]) });
			}
		}
		return list;
	}

	function findBridge(world, start, rng) {
		var startChunk = world.owner[keyOf(start.x, start.y)];
		var dirs = shuffle(["right", "left", "up", "down"], rng);
		var queue = [];
		var seen = {};
		seen[keyOf(start.x, start.y)] = true;
		var d;
		for (d = 0; d < dirs.length; d++) {
			var first = step(start.x, start.y, dirs[d]);
			var firstKey = keyOf(first.x, first.y);
			if (!inGrid(first.x, first.y) || world.occupied[firstKey] || seen[firstKey]) continue;
			seen[firstKey] = true;
			queue.push({ x: first.x, y: first.y, path: [first] });
		}
		var guard = 0;
		while (queue.length && guard++ < 80) {
			var cur = queue.shift();
			if (cur.path.length > 4) continue;
			var near = shuffle(["right", "left", "up", "down"], rng);
			var n;
			for (n = 0; n < near.length; n++) {
				var next = step(cur.x, cur.y, near[n]);
				var nextKey = keyOf(next.x, next.y);
				if (world.owner[nextKey] && world.owner[nextKey] !== startChunk) {
					return { cells: cur.path, end: world.owner[nextKey] };
				}
			}
			if (cur.path.length >= 4) continue;
			for (n = 0; n < near.length; n++) {
				var open = step(cur.x, cur.y, near[n]);
				var openKey = keyOf(open.x, open.y);
				if (!inGrid(open.x, open.y) || world.occupied[openKey] || seen[openKey]) continue;
				seen[openKey] = true;
				queue.push({ x: open.x, y: open.y, path: cur.path.concat([open]) });
			}
		}
		return null;
	}

	function addRungs(world, rng) {
		var cells = shuffle(corridorCells(world), rng);
		var added = 0;
		var i;
		for (i = 0; i < cells.length && added < 7; i++) {
			var dirs = shuffle(["up", "down", "right", "left"], rng);
			var d;
			for (d = 0; d < dirs.length && added < 7; d++) {
				var gap;
				for (gap = 2; gap <= 4; gap++) {
					var between = [];
					var pos = { x: cells[i].x, y: cells[i].y };
					var open = true;
					var s;
					for (s = 1; s < gap; s++) {
						pos = step(pos.x, pos.y, dirs[d]);
						if (!inGrid(pos.x, pos.y) || world.occupied[keyOf(pos.x, pos.y)]) {
							open = false;
							break;
						}
						between.push({ x: pos.x, y: pos.y });
					}
					if (!open) continue;
					pos = step(pos.x, pos.y, dirs[d]);
					var owner = world.owner[keyOf(pos.x, pos.y)];
					var startChunk = world.owner[keyOf(cells[i].x, cells[i].y)];
					if (!owner || owner === startChunk) continue;
					var shot = snapshot(world);
					if (commitPath(world, between, startChunk, owner)) added += 1;
					else restore(world, shot);
					break;
				}
			}
		}
		return added;
	}

	function addLoops(world, rng) {
		var added = 0;
		var attempt;
		for (attempt = 0; attempt < 18 && added < 5; attempt++) {
			var cells = corridorCells(world);
			if (!cells.length) return added;
			var start = cells[Math.floor(rng() * cells.length)];
			var bridge = findBridge(world, start, rng);
			if (!bridge) continue;
			var shot = snapshot(world);
			var tail = commitPath(world, bridge.cells, world.owner[keyOf(start.x, start.y)], bridge.end);
			if (!tail) restore(world, shot);
			else added += 1;
		}
		return added;
	}

	var WALL = 6;
	var OPENING = 8;

	function addPiece(rooms, nextId, x, y, w, h, role) {
		var rect = { id: nextId.value, x: x, y: y, w: w, h: h, role: role, links: [] };
		nextId.value += 1;
		rooms.push(rect);
		return rect;
	}

	function openingShift(span, size, bias) {
		var slack = span - size;
		if (slack < 0) return -1;
		if (bias === "floor") return slack;
		if (bias === "high") return 0;
		return Math.floor(slack / 2);
	}

	function placeOpening(rooms, nextId, a, b, bias, size) {
		var left = a;
		var right = b;
		var piece = null;
		if (a.x + a.w <= b.x || b.x + b.w <= a.x) {
			if (b.x + b.w <= a.x) {
				left = b;
				right = a;
			}
			var y0 = Math.max(left.y, right.y);
			var y1 = Math.min(left.y + left.h, right.y + right.h);
			var spanY = y1 - y0;
			var openY = Math.min(size, spanY);
			var shiftY = openingShift(spanY, openY, bias);
			if (openY < STROKE || shiftY < 0) return null;
			piece = {
				x: left.x + left.w,
				y: y0 + shiftY,
				w: right.x - (left.x + left.w),
				h: openY,
				role: "door",
				links: [],
			};
		} else if (a.y + a.h <= b.y || b.y + b.h <= a.y) {
			var top = a.y + a.h <= b.y ? a : b;
			var bottom = top === a ? b : a;
			var x0 = Math.max(top.x, bottom.x);
			var x1 = Math.min(top.x + top.w, bottom.x + bottom.w);
			var spanX = x1 - x0;
			var openX = Math.min(size, spanX);
			var shiftX = openingShift(spanX, openX, bias);
			if (openX < STROKE || shiftX < 0) return null;
			piece = {
				x: x0 + shiftX,
				y: top.y + top.h,
				w: openX,
				h: bottom.y - (top.y + top.h),
				role: "door",
				links: [],
			};
			left = top;
			right = bottom;
		} else return null;
		if (piece.w < 1 || piece.h < 1) return null;
		if (!sharesDoor(piece, left) || !sharesDoor(piece, right)) return null;
		var i;
		for (i = 0; i < rooms.length; i++) {
			if (rooms[i] === left || rooms[i] === right) continue;
			if (overlaps(piece, rooms[i]) || tooClose(piece, rooms[i])) return null;
		}
		piece.id = nextId.value;
		nextId.value += 1;
		rooms.push(piece);
		link(left, piece, directionTo(left, piece));
		link(right, piece, directionTo(right, piece));
		return piece;
	}

	function directionTo(from, to) {
		if (to.x >= from.x + from.w) return "right";
		if (from.x >= to.x + to.w) return "left";
		if (to.y >= from.y + from.h) return "down";
		return "up";
	}

	function mustOpen(rooms, nextId, a, b, bias, size, seed, label) {
		var door = placeOpening(rooms, nextId, a, b, bias, size);
		if (!door) throw new Error("小屋门没放上 " + label + " 种子 " + seed);
		return door;
	}

	function generateHut(options) {
		var seed = options.seed >>> 0;
		var rng = mulberry32(seed);
		var verticality = Math.max(0, Math.min(1, options.verticality == null ? 0.45 : options.verticality));
		var length = Math.max(5, Math.min(12, options.length || 8));
		var rooms = [];
		var nextId = { value: 1 };
		var extra = (length - 5) * 3;
		var f3H = 18 + Math.floor(verticality * 4) + Math.floor(rng() * 3);
		var f2H = 20 + Math.floor(verticality * 4) + Math.floor(rng() * 4);
		var f1H = 18 + Math.floor(verticality * 5) + Math.floor(rng() * 3);
		var baseH = 15 + Math.floor(rng() * 4);
		var atticH = 12 + Math.floor(rng() * 3);
		var stairW = 12;
		var zLw = 32 + extra + Math.floor(rng() * 14);
		var zMw = 16 + Math.floor(rng() * 8);
		var zRw = 40 + Math.floor(extra * 0.5) + Math.floor(rng() * 12);
		var porchW = 16 + Math.floor(rng() * 6);
		var porchH = 11;
		var zL = 26 + porchW;
		var zM = zL + zLw + WALL;
		var zR = zM + zMw + WALL;
		var bodyRight = zR + zRw;
		var atticY = 16;
		var f3Y = atticY + atticH + WALL;
		var f2Y = f3Y + f3H + WALL;
		var f1Y = f2Y + f2H + WALL;
		var baseY = f1Y + f1H + WALL;
		var up23 = addPiece(rooms, nextId, zL, f3Y, stairW, f3H, "room");
		var f3bW = 20 + Math.floor(rng() * 8);
		var f3aX = zL + stairW + WALL;
		var f3aW = bodyRight - f3aX - WALL - f3bW;
		if (f3aW < 36) {
			f3bW = Math.max(18, bodyRight - f3aX - WALL - 36);
			f3aW = bodyRight - f3aX - WALL - f3bW;
		}
		var f3a = addPiece(rooms, nextId, f3aX, f3Y, f3aW, f3H, "room");
		var f3b = addPiece(rooms, nextId, f3aX + f3aW + WALL, f3Y + 6, f3bW, f3H - 6, "room");
		var up12 = addPiece(rooms, nextId, zR, f2Y, stairW, f2H, "room");
		var f2left = addPiece(rooms, nextId, zL, f2Y, zLw, f2H, "room");
		var f2mid = addPiece(rooms, nextId, zM, f2Y + 6, zMw, f2H - 6, "room");
		var f2rightX = zR + stairW + WALL;
		var f2right = addPiece(rooms, nextId, f2rightX, f2Y + 3, bodyRight - f2rightX, f2H - 3, "room");
		var hall = addPiece(rooms, nextId, zL, f1Y, zR - WALL - zL, f1H, "room");
		var f1right = addPiece(rooms, nextId, zR, f1Y + 5, zRw, f1H - 5, "room");
		var porch = addPiece(rooms, nextId, zL - WALL - porchW, f1Y + f1H - porchH, porchW, porchH, "room");
		var balconyH = 10;
		var balcony = addPiece(rooms, nextId, bodyRight + WALL, f2right.y + Math.max(0, Math.floor((f2right.h - balconyH) / 2)), 16 + Math.floor(rng() * 6), balconyH, "room");
		var baseA = addPiece(rooms, nextId, zL, baseY, zLw + 10, baseH, "room");
		var baseBX = baseA.x + baseA.w + WALL;
		var baseB = addPiece(rooms, nextId, baseBX, baseY + 4, Math.max(18, bodyRight - baseBX), baseH - 4, "room");
		var atticW = Math.max(24, Math.floor((bodyRight - zL) * 0.3));
		var atticX = zL + Math.floor((bodyRight - zL - atticW) / 2);
		if (atticX < f3a.x + 4) atticX = f3a.x + 4;
		if (atticX + atticW > f3a.x + f3a.w - 4) atticW = f3a.x + f3a.w - 4 - atticX;
		var attic = addPiece(rooms, nextId, atticX, atticY, Math.max(18, atticW), atticH, "room");
		var shaft = addPiece(rooms, nextId, bodyRight + WALL, f3b.y - 14, 12, f3b.h + 14, "room");
		var landing = addPiece(rooms, nextId, shaft.x + shaft.w, shaft.y, 20 + Math.floor(rng() * 6), 10, "room");
		link(shaft, landing, "right");
		mustOpen(rooms, nextId, porch, hall, "floor", OPENING, seed, "门口");
		mustOpen(rooms, nextId, hall, f1right, "floor", OPENING, seed, "一楼");
		mustOpen(rooms, nextId, up12, f1right, "mid", OPENING, seed, "上二楼");
		mustOpen(rooms, nextId, up12, f2mid, "floor", OPENING, seed, "二楼中");
		mustOpen(rooms, nextId, up12, f2right, "floor", OPENING, seed, "二楼右");
		mustOpen(rooms, nextId, f2left, f2mid, "floor", OPENING, seed, "二楼左");
		mustOpen(rooms, nextId, up23, f2left, "mid", OPENING, seed, "上三楼");
		mustOpen(rooms, nextId, up23, f3a, "floor", OPENING, seed, "三楼");
		mustOpen(rooms, nextId, f3a, f3b, "floor", OPENING, seed, "三楼右");
		mustOpen(rooms, nextId, attic, f3a, "mid", OPENING, seed, "阁楼");
		mustOpen(rooms, nextId, hall, baseA, "floor", OPENING, seed, "地下室");
		mustOpen(rooms, nextId, baseA, baseB, "floor", OPENING, seed, "地下隔间");
		mustOpen(rooms, nextId, f2right, balcony, "mid", balconyH, seed, "阳台");
		mustOpen(rooms, nextId, f3b, shaft, "mid", OPENING, seed, "树根");
		if (!gapOk(rooms)) throw new Error("小屋重叠 种子 " + seed);
		var map = raster(rooms, seed, verticality, "hut");
		if (componentCount(map) !== 1) throw new Error("小屋不连通 种子 " + seed);
		return map;
	}

	function spanX(a, b) {
		return Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
	}

	function spanY(a, b) {
		return Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
	}

	function generateTower(options) {
		var seed = options.seed >>> 0;
		var rng = mulberry32(seed);
		var verticality = Math.max(0, Math.min(1, options.verticality == null ? 0.45 : options.verticality));
		var length = Math.max(5, Math.min(12, options.length || 8));
		var floors = 5 + (length - 5);
		var rooms = [];
		var nextId = { value: 1 };
		var wall = WALL;

		function fits(rect) {
			if (rect.w < 9 || rect.h < 9 || rect.x < 4 || rect.y < 4) return false;
			var i;
			for (i = 0; i < rooms.length; i++) {
				if (overlaps(rect, rooms[i]) || tooClose(rect, rooms[i])) return false;
			}
			return true;
		}

		function placeRoom(x, y, w, h) {
			var rect = { x: x, y: y, w: w, h: h };
			if (!fits(rect)) return null;
			return addPiece(rooms, nextId, x, y, w, h, "room");
		}

		function removeLast(piece) {
			if (rooms[rooms.length - 1] !== piece) throw new Error("高塔撤回错位 种子 " + seed);
			var i;
			for (i = 0; i < rooms.length; i++) unlink(rooms[i], piece.id);
			rooms.pop();
			nextId.value -= 1;
		}

		function connect(a, b) {
			var bias = rng() < 0.34 ? "floor" : rng() < 0.5 ? "high" : "mid";
			var size = STROKE + 1 + Math.floor(rng() * 4);
			return placeOpening(rooms, nextId, a, b, bias, size);
		}

		function beside(host, side, w, h, yShift) {
			var x = side < 0 ? host.x - wall - w : host.x + host.w + wall;
			var slack = host.h - h;
			var y = slack >= 0 ? host.y + yShift : host.y + yShift;
			if (slack >= 0 && yShift > slack) y = host.y + slack;
			if (y < 4) y = 4;
			return placeRoom(x, y, w, h);
		}

		var originX = 30 + Math.floor(rng() * 18);
		var peak = placeRoom(originX, 10, 14 + Math.floor(rng() * 8), 11 + Math.floor(rng() * 4));
		if (!peak) throw new Error("高塔起点失败 种子 " + seed);
		var current = peak;
		var spine = [peak];
		var dir = rng() < 0.5 ? -1 : 1;
		var sideCount = 0;

		function addPocket(host, side) {
			var w = 11 + Math.floor(rng() * 10);
			var h = 9 + Math.floor(rng() * 7);
			var shift = Math.floor(rng() * Math.max(1, host.h - h + 4));
			var room = beside(host, side, w, h, shift);
			if (!room) {
				room = beside(host, -side, w, h, 0);
				if (!room) return null;
			}
			if (spanY(host, room) < STROKE || !connect(host, room)) {
				removeLast(room);
				return null;
			}
			sideCount += 1;
			return room;
		}

		function addParallel(host, side) {
			var w = 10 + Math.floor(rng() * 6);
			var h = 18 + Math.floor(verticality * 14) + Math.floor(rng() * 12);
			var y = host.y + Math.floor(rng() * 5);
			var x = side < 0 ? host.x - wall - w : host.x + host.w + wall;
			var room = placeRoom(x, y, w, h);
			if (!room || spanY(host, room) < 8 || !connect(host, room)) {
				if (room) removeLast(room);
				return null;
			}
			sideCount += 1;
			if (rng() < 0.7) {
				var sw = 10 + Math.floor(rng() * 5);
				var sh = 14 + Math.floor(verticality * 10) + Math.floor(rng() * 8);
				var down = rng() < 0.6;
				var sy = down ? room.y + room.h + wall : room.y - wall - sh;
				var sx = room.x + Math.floor((room.w - sw) / 2) + (rng() < 0.5 ? -2 : 2);
				var minX = room.x + 8 - sw;
				var maxX = room.x + room.w - 8;
				if (sx < minX) sx = minX;
				if (sx > maxX) sx = maxX;
				var shaft = placeRoom(sx, sy, sw, sh);
				if (shaft && spanX(room, shaft) >= 8 && connect(room, shaft)) {
					var s;
					for (s = 0; s < spine.length; s++) {
						var other = spine[s];
						if (other === host) continue;
						if (spanY(shaft, other) < 8) continue;
						var gap = shaft.x >= other.x + other.w ? shaft.x - (other.x + other.w) : other.x - (shaft.x + shaft.w);
						if (gap < wall || gap > wall + 8) continue;
						if (connect(shaft, other)) break;
					}
				} else if (shaft) removeLast(shaft);
			}
			return room;
		}

		function trySplit(parent) {
			var leftW = 10 + Math.floor(rng() * 4);
			var rightW = 10 + Math.floor(rng() * 4);
			if (parent.w < leftW + wall + rightW) return null;
			var leftX = parent.x + Math.floor(rng() * 3);
			var rightX = parent.x + parent.w - rightW - Math.floor(rng() * 3);
			if (rightX < leftX + leftW + wall) rightX = leftX + leftW + wall;
			if (rightX + rightW > parent.x + parent.w + 2) return null;
			if (spanX(parent, { x: leftX, y: 0, w: leftW, h: 1 }) < 8) return null;
			if (spanX(parent, { x: rightX, y: 0, w: rightW, h: 1 }) < 8) return null;
			var leftH = 24 + Math.floor(verticality * 14) + Math.floor(rng() * 10);
			var rightH = 16 + Math.floor(verticality * 8) + Math.floor(rng() * 8);
			if (rng() < 0.5) {
				var swap = leftH;
				leftH = rightH;
				rightH = swap;
			}
			if (Math.abs(leftH - rightH) < 12) {
				if (leftH >= rightH) leftH += 12;
				else rightH += 12;
			}
			var y0 = parent.y + parent.h + wall;
			var left = placeRoom(leftX, y0, leftW, leftH);
			if (!left || !connect(parent, left)) {
				if (left) removeLast(left);
				return null;
			}
			var right = placeRoom(rightX, y0, rightW, rightH);
			if (!right || !connect(parent, right)) {
				if (right) removeLast(right);
				spine.push(left);
				return left;
			}
			sideCount += 1;
			var longer = left.h >= right.h ? left : right;
			var shorter = longer === left ? right : left;
			var landY = shorter.y + shorter.h + wall;
			var landX = shorter.x < longer.x ? shorter.x : longer.x + longer.w + wall;
			var landW = shorter.x < longer.x ? longer.x - wall - landX : shorter.x + shorter.w - landX;
			if (landY + 8 < longer.y + longer.h && landW >= 10) {
				var land = placeRoom(landX, landY, landW, 11 + Math.floor(rng() * 3));
				if (land && spanY(longer, land) >= STROKE && spanX(shorter, land) >= 8) {
					var downDoor = connect(shorter, land);
					var sideDoor = downDoor ? connect(longer, land) : null;
					if (downDoor && sideDoor) {
						spine.push(longer);
						return longer;
					}
					if (downDoor) removeLast(downDoor);
					removeLast(land);
				} else if (land) removeLast(land);
			}
			spine.push(longer);
			return longer;
		}

		var step;
		for (step = 0; step < floors; step++) {
			if (rng() < 0.22 + (1 - verticality) * 0.2) dir = -dir;
			var split = current.w >= 28 && rng() < 0.42;
			if (split) {
				var forked = trySplit(current);
				if (forked) {
					current = forked;
					continue;
				}
			}
			var tall = rng() < 0.28 + verticality * 0.45;
			var wide = !tall && rng() < 0.55 - verticality * 0.2;
			var w;
			var h;
			if (tall) {
				w = 10 + Math.floor(rng() * 7);
				h = 22 + Math.floor(verticality * 16) + Math.floor(rng() * 12);
			} else if (wide) {
				w = 26 + Math.floor(rng() * 16);
				h = 10 + Math.floor(rng() * 5);
			} else {
				w = 14 + Math.floor(rng() * 12);
				h = 12 + Math.floor(verticality * 8) + Math.floor(rng() * 8);
			}
			var ny = current.y + current.h + wall;
			var placed = null;
			var attempt;
			for (attempt = 0; attempt < 8 && !placed; attempt++) {
				var tryW = Math.max(10, w - (attempt > 2 ? attempt : 0));
				var tryH = Math.max(10, h - (attempt > 4 ? (attempt - 4) * 4 : 0));
				var drift = dir * (3 + Math.floor(rng() * (wide ? 14 : 9)));
				var desired = current.x + Math.floor((current.w - tryW) / 2) + drift + (attempt % 2 === 0 ? attempt : -attempt);
				var need = Math.min(8, tryW, current.w);
				var minX = current.x + need - tryW;
				var maxX = current.x + current.w - need;
				if (desired < originX - 36) desired = originX - 36;
				if (desired > originX + 48) desired = originX + 48;
				if (desired < minX) desired = minX;
				if (desired > maxX) desired = maxX;
				if (desired < 6) desired = 6;
				var room = placeRoom(desired, ny, tryW, tryH);
				if (!room || spanX(current, room) < need || !connect(current, room)) {
					if (room) removeLast(room);
					continue;
				}
				placed = room;
			}
			if (!placed) {
				var fallback;
				var hostIndex;
				for (hostIndex = spine.length - 1; hostIndex >= 0 && !placed; hostIndex--) {
					var host = spine[hostIndex];
					var dropY = host.y + host.h + wall;
					var dropW = Math.min(12, host.w);
					var dropX;
					for (dropX = host.x; dropX + dropW <= host.x + host.w && !placed; dropX += 2) {
						fallback = placeRoom(dropX, dropY, dropW, 12);
						if (fallback && spanX(host, fallback) >= Math.min(8, dropW) && connect(host, fallback)) placed = fallback;
						else if (fallback) removeLast(fallback);
					}
				}
			}
			if (!placed) throw new Error("高塔爬升中断 种子 " + seed);
			spine.push(placed);
			current = placed;
			if (rng() < 0.48) addPocket(placed, rng() < 0.5 ? -1 : 1);
			else if (rng() < 0.55) addParallel(placed, dir);
		}
		var guard = 0;
		while (sideCount < 2 && guard < spine.length) {
			addPocket(spine[guard], guard % 2 === 0 ? -1 : 1);
			guard += 1;
		}
		if (sideCount < 2) throw new Error("高塔没有分支 种子 " + seed);
		if (!gapOk(rooms)) throw new Error("高塔重叠 种子 " + seed);
		var map = raster(rooms, seed, verticality, "tower");
		if (componentCount(map) !== 1) throw new Error("高塔不连通 种子 " + seed);
		if (map.height < map.width * 1.15) throw new Error("高塔不够高 种子 " + seed);
		return map;
	}

	function generate(options) {
		var layout = options.layout === "hut" ? "hut" : options.layout === "tower" ? "tower" : "road";
		if (layout === "hut") return generateHut(options);
		if (layout === "tower") return generateTower(options);
		var seed = options.seed >>> 0;
		var rng = mulberry32(seed);
		var verticality = Math.max(0, Math.min(1, options.verticality));
		var target = Math.max(5, Math.min(12, options.length || 8));
		var world = createWorld();
		var entrance = attachRoom(world, 2, 11, 3, 1, null);
		var main = [entrance];
		var current = entrance;
		var guard = 0;
		while (main.length < target && guard++ < target * 6) {
			var next = extendFrom(world, current, rng, verticality, 3, 5);
			if (!next) {
				current = main[Math.floor(rng() * main.length)];
				continue;
			}
			main.push(next);
			current = next;
		}
		var branches = Math.max(2, Math.round(target * 0.45));
		var made = 0;
		guard = 0;
		while (made < branches && guard++ < branches * 4) {
			var host = main[Math.floor(rng() * main.length)];
			if (extendFrom(world, host, rng, Math.max(verticality, 0.4), 2, 5)) made += 1;
		}
		addRungs(world, rng);
		addLoops(world, rng);
		return raster(world.chunks, seed, verticality, "road");
	}

	function raster(rooms, seed, verticality, layout) {
		var minX = 9999;
		var minY = 9999;
		var maxX = 0;
		var maxY = 0;
		var i;
		for (i = 0; i < rooms.length; i++) {
			minX = Math.min(minX, rooms[i].x);
			minY = Math.min(minY, rooms[i].y);
			maxX = Math.max(maxX, rooms[i].x + rooms[i].w - 1);
			maxY = Math.max(maxY, rooms[i].y + rooms[i].h - 1);
		}
		var width = maxX - minX + 1;
		var height = maxY - minY + 1;
		var owners = [];
		var n;
		for (n = 0; n < width * height; n++) owners.push(0);
		var chunks = [];
		for (i = 0; i < rooms.length; i++) {
			var room = rooms[i];
			var chunk = {
				id: room.id,
				x: room.x - minX,
				y: room.y - minY,
				w: room.w,
				h: room.h,
				role: room.role,
				gx: room.gx,
				gy: room.gy,
				cw: room.cw,
				ch: room.ch,
				links: room.links.map(function (item) {
					return { dir: item.dir, id: item.id };
				}),
			};
			chunks.push(chunk);
			var y;
			var x;
			for (y = 0; y < room.h; y++) {
				for (x = 0; x < room.w; x++) owners[(chunk.y + y) * width + chunk.x + x] = room.id;
			}
		}
		return {
			seed: seed,
			revision: 1,
			width: width,
			height: height,
			verticality: verticality,
			layout: layout || "road",
			owners: owners,
			chunks: chunks,
		};
	}

	function insideBoard(piece, board) {
		return piece.x >= 2 && piece.y >= 2 && piece.x + piece.w <= board.width - 2 && piece.y + piece.h <= board.height - 2;
	}

	function fits(piece, anchors, rooms, board) {
		var i;
		if (!insideBoard(piece, board)) return false;
		for (i = 0; i < anchors.length; i++) {
			if (overlaps(piece, anchors[i]) || !sharesDoor(piece, anchors[i])) return false;
		}
		for (i = 0; i < rooms.length; i++) {
			if (anchors.indexOf(rooms[i]) >= 0) continue;
			if (tooClose(piece, rooms[i])) return false;
		}
		return true;
	}

	function slide(parent, dir, w, h, shift) {
		var x;
		var y;
		if (dir === "right") {
			x = parent.x + parent.w;
			y = parent.y + Math.floor((parent.h - h) / 2) + shift;
		} else if (dir === "left") {
			x = parent.x - w;
			y = parent.y + Math.floor((parent.h - h) / 2) + shift;
		} else if (dir === "down") {
			y = parent.y + parent.h;
			x = parent.x + Math.floor((parent.w - w) / 2) + shift;
		} else {
			y = parent.y - h;
			x = parent.x + Math.floor((parent.w - w) / 2) + shift;
		}
		return { x: x, y: y, w: w, h: h };
	}

	function orderedDirs(rng, verticality) {
		var pool = [];
		var i;
		for (i = 0; i < 8; i++) pool.push("right");
		pool.push("left");
		var vertical = 1 + Math.round(verticality * 4);
		for (i = 0; i < vertical; i++) {
			pool.push("up");
			pool.push("down");
		}
		var result = [];
		while (pool.length && result.length < 4) {
			var index = Math.floor(rng() * pool.length);
			var dir = pool.splice(index, 1)[0];
			if (result.indexOf(dir) < 0) result.push(dir);
		}
		["right", "left", "up", "down"].forEach(function (dir) {
			if (result.indexOf(dir) < 0) result.push(dir);
		});
		return result;
	}

	function placeAgainst(parent, dir, w, h, role, rooms, board, nextId) {
		var shifts = [0, -2, 2, -4, 4];
		var s;
		for (s = 0; s < shifts.length; s++) {
			var piece = slide(parent, dir, w, h, shifts[s]);
			piece.id = nextId.value;
			piece.role = role;
			piece.links = [];
			if (!fits(piece, [parent], rooms, board)) continue;
			nextId.value += 1;
			rooms.push(piece);
			link(parent, piece, dir);
			return piece;
		}
		return null;
	}

	function placeCorridor(parent, rooms, board, rng, verticality, nextId) {
		var dirs = orderedDirs(rng, verticality);
		var d;
		for (d = 0; d < dirs.length; d++) {
			var horizontal = dirs[d] === "left" || dirs[d] === "right";
			var len = 8 + Math.floor(rng() * 8);
			var piece = placeAgainst(parent, dirs[d], horizontal ? len : STROKE, horizontal ? STROKE : len, "corridor", rooms, board, nextId);
			if (piece) return piece;
		}
		return null;
	}

	function placeRoom(parent, rooms, board, rng, verticality, nextId) {
		var dirs = orderedDirs(rng, verticality);
		var sizes = [
			[14, 7],
			[21, 7],
			[14, 14],
			[7, 14],
		];
		shuffle(sizes, rng);
		var d;
		var s;
		for (d = 0; d < dirs.length; d++) {
			for (s = 0; s < sizes.length; s++) {
				var piece = placeAgainst(parent, dirs[d], sizes[s][0], sizes[s][1], "room", rooms, board, nextId);
				if (piece) return piece;
			}
		}
		return null;
	}

	function straightBetween(a, b) {
		if (a.x + a.w <= b.x) {
			var gap = b.x - (a.x + a.w);
			var top = Math.max(a.y, b.y);
			var bottom = Math.min(a.y + a.h, b.y + b.h);
			if (gap >= 4 && gap <= 28 && bottom - top >= STROKE) {
				return { x: a.x + a.w, y: top + Math.floor((bottom - top - STROKE) / 2), w: gap, h: STROKE, role: "corridor", links: [] };
			}
		}
		if (a.y + a.h <= b.y) {
			var gapY = b.y - (a.y + a.h);
			var left = Math.max(a.x, b.x);
			var right = Math.min(a.x + a.w, b.x + b.w);
			if (gapY >= 4 && gapY <= 24 && right - left >= STROKE) {
				return { x: left + Math.floor((right - left - STROKE) / 2), y: a.y + a.h, w: STROKE, h: gapY, role: "corridor", links: [] };
			}
		}
		return null;
	}

	function connectPair(a, b, rooms, board, nextId) {
		var order = [straightBetween(a, b), straightBetween(b, a)];
		var i;
		for (i = 0; i < order.length; i++) {
			var piece = order[i];
			if (!piece || !fits(piece, [a, b], rooms, board)) continue;
			piece.id = nextId.value;
			nextId.value += 1;
			rooms.push(piece);
			link(a, piece, piece.x >= a.x + a.w ? "right" : piece.y >= a.y + a.h ? "down" : piece.x + piece.w <= a.x ? "left" : "up");
			link(b, piece, piece.x >= b.x + b.w ? "right" : piece.y >= b.y + b.h ? "down" : piece.x + piece.w <= b.x ? "left" : "up");
			return piece;
		}
		return null;
	}

	function findRoot(parent, id) {
		if (parent[id] == null) parent[id] = id;
		if (parent[id] !== id) parent[id] = findRoot(parent, parent[id]);
		return parent[id];
	}

	function reconnect(rooms, board, nextId) {
		var guard = 0;
		while (guard++ < 6) {
			var parent = {};
			var i;
			for (i = 0; i < rooms.length; i++) findRoot(parent, rooms[i].id);
			for (i = 0; i < rooms.length; i++) {
				var n;
				for (n = 0; n < rooms[i].links.length; n++) parent[findRoot(parent, rooms[i].id)] = findRoot(parent, rooms[i].links[n].id);
			}
			var groups = {};
			for (i = 0; i < rooms.length; i++) {
				var root = findRoot(parent, rooms[i].id);
				if (!groups[root]) groups[root] = [];
				groups[root].push(rooms[i]);
			}
			var keys = Object.keys(groups);
			if (keys.length < 2) return;
			var connected = false;
			var a;
			var b;
			for (a = 0; a < groups[keys[0]].length && !connected; a++) {
				for (b = 0; b < groups[keys[1]].length && !connected; b++) {
					if (connectPair(groups[keys[0]][a], groups[keys[1]][b], rooms, board, nextId)) connected = true;
				}
			}
			if (!connected) return;
		}
	}

	function cloneChunks(chunks) {
		return chunks.map(function (chunk) {
			return {
				id: chunk.id,
				x: chunk.x,
				y: chunk.y,
				w: chunk.w,
				h: chunk.h,
				role: chunk.role,
				links: (chunk.links || []).map(function (item) {
					return { dir: item.dir, id: item.id };
				}),
			};
		});
	}

	function redrawHut(map, ids) {
		var selected = {};
		var i;
		for (i = 0; i < ids.length; i++) selected[ids[i]] = true;
		var rooms = cloneChunks(map.chunks);
		var rng = mulberry32((map.seed + map.revision * 97) >>> 0);
		var deltas = [
			[4, 0],
			[-4, 0],
			[0, 4],
			[0, -4],
			[8, 0],
			[-8, 0],
			[0, 8],
			[0, -8],
			[4, 4],
			[-4, -4],
		];
		var changed = false;
		for (i = 0; i < rooms.length; i++) {
			if (!selected[rooms[i].id]) continue;
			var original = { x: rooms[i].x, y: rooms[i].y, w: rooms[i].w, h: rooms[i].h };
			var tries = shuffle(deltas.slice(), rng);
			var t;
			var fitted = false;
			for (t = 0; t < tries.length; t++) {
				if (rooms[i].role === "door") {
					rooms[i].x = original.x + tries[t][0];
					rooms[i].y = original.y + tries[t][1];
					rooms[i].w = original.w;
					rooms[i].h = original.h;
				} else {
					rooms[i].x = original.x;
					rooms[i].y = original.y;
					rooms[i].w = Math.max(OPENING, original.w + tries[t][0]);
					rooms[i].h = Math.max(OPENING, original.h + tries[t][1]);
				}
				if (gapOk(rooms)) {
					fitted = true;
					changed = true;
					break;
				}
			}
			if (!fitted) {
				rooms[i].x = original.x;
				rooms[i].y = original.y;
				rooms[i].w = original.w;
				rooms[i].h = original.h;
			}
		}
		if (!changed) return map;
		var result = raster(rooms, map.seed, map.verticality, "hut");
		result.revision = map.revision + 1;
		if (componentCount(result) !== 1) return map;
		return result;
	}

	function redrawTower(map, ids) {
		var selected = {};
		var i;
		for (i = 0; i < ids.length; i++) selected[ids[i]] = true;
		var rooms = cloneChunks(map.chunks);
		var rng = mulberry32((map.seed + map.revision * 97) >>> 0);
		var deltas = [
			[4, 0],
			[-4, 0],
			[6, 0],
			[-6, 0],
			[0, 2],
			[0, -2],
		];
		var changed = false;
		for (i = 0; i < rooms.length; i++) {
			if (!selected[rooms[i].id]) continue;
			var original = { x: rooms[i].x, y: rooms[i].y, w: rooms[i].w, h: rooms[i].h };
			var tries = shuffle(deltas.slice(), rng);
			var t;
			var fitted = false;
			for (t = 0; t < tries.length; t++) {
				rooms[i].x = original.x + tries[t][0];
				rooms[i].y = original.y;
				rooms[i].w = Math.max(14, original.w + tries[t][1]);
				rooms[i].h = original.h;
				if (gapOk(rooms)) {
					fitted = true;
					changed = true;
					break;
				}
			}
			if (!fitted) {
				rooms[i].x = original.x;
				rooms[i].y = original.y;
				rooms[i].w = original.w;
				rooms[i].h = original.h;
			}
		}
		if (!changed) return map;
		var result = raster(rooms, map.seed, map.verticality, "tower");
		result.revision = map.revision + 1;
		return result;
	}

	function redraw(map, ids) {
		if (map.layout === "hut") return redrawHut(map, ids);
		if (map.layout === "tower") return redrawTower(map, ids);
		var selected = {};
		var i;
		for (i = 0; i < ids.length; i++) selected[ids[i]] = true;
		var kept = [];
		var removed = false;
		for (i = 0; i < map.chunks.length; i++) {
			if (selected[map.chunks[i].id]) removed = true;
			else kept.push(map.chunks[i]);
		}
		if (!removed) return map;
		var margin = 28;
		var rooms = cloneChunks(kept);
		for (i = 0; i < rooms.length; i++) {
			rooms[i].x += margin;
			rooms[i].y += margin;
			rooms[i].links = rooms[i].links.filter(function (item) {
				return !selected[item.id];
			});
		}
		var board = { width: map.width + margin * 2, height: map.height + margin * 2 };
		var nextId = { value: 1 };
		for (i = 0; i < map.chunks.length; i++) nextId.value = Math.max(nextId.value, map.chunks[i].id + 1);
		var rng = mulberry32((map.seed + map.revision * 97) >>> 0);
		var sockets = [];
		for (i = 0; i < rooms.length; i++) {
			var original = null;
			var c;
			for (c = 0; c < map.chunks.length; c++) if (map.chunks[c].id === rooms[i].id) original = map.chunks[c];
			if (!original) continue;
			for (c = 0; c < original.links.length; c++) if (selected[original.links[c].id]) sockets.push(rooms[i]);
		}
		var s;
		for (s = 0; s < sockets.length; s++) {
			var corridor = placeCorridor(sockets[s], rooms, board, rng, map.verticality, nextId);
			if (corridor) placeRoom(corridor, rooms, board, rng, map.verticality, nextId);
		}
		reconnect(rooms, board, nextId);
		var result = raster(rooms, map.seed, map.verticality, "road");
		result.revision = map.revision + 1;
		if (componentCount(result) !== 1) return map;
		return result;
	}

	function componentCount(map) {
		var seen = {};
		var count = 0;
		var y;
		var x;
		for (y = 0; y < map.height; y++) {
			for (x = 0; x < map.width; x++) {
				var id = y * map.width + x;
				if (map.owners[id] === 0 || seen[id]) continue;
				count++;
				var stack = [id];
				seen[id] = true;
				while (stack.length) {
					var current = stack.pop();
					var cx = current % map.width;
					var cy = (current - cx) / map.width;
					var near = [
						[cx - 1, cy],
						[cx + 1, cy],
						[cx, cy - 1],
						[cx, cy + 1],
					];
					var n;
					for (n = 0; n < near.length; n++) {
						var nx = near[n][0];
						var ny = near[n][1];
						if (nx < 0 || ny < 0 || nx >= map.width || ny >= map.height) continue;
						var ni = ny * map.width + nx;
						if (map.owners[ni] === 0 || seen[ni]) continue;
						seen[ni] = true;
						stack.push(ni);
					}
				}
			}
		}
		return count;
	}

	function rowsOf(map) {
		var rows = [];
		var y;
		var x;
		for (y = 0; y < map.height; y++) {
			var line = "";
			for (x = 0; x < map.width; x++) line += map.owners[y * map.width + x] ? "1" : "0";
			rows.push(line);
		}
		return rows;
	}

	function exportData(map) {
		return { seed: map.seed, revision: map.revision, width: map.width, height: map.height, chunks: map.chunks, rows: rowsOf(map) };
	}

	function gapOk(chunks) {
		var i;
		var j;
		for (i = 0; i < chunks.length; i++) {
			for (j = i + 1; j < chunks.length; j++) {
				if (overlaps(chunks[i], chunks[j])) return false;
				var linked = false;
				var n;
				for (n = 0; n < chunks[i].links.length; n++) if (chunks[i].links[n].id === chunks[j].id) linked = true;
				if (!linked && tooClose(chunks[i], chunks[j])) return false;
				if (linked && !sharesDoor(chunks[i], chunks[j])) return false;
			}
		}
		return true;
	}

	function cycleCount(chunks) {
		var edges = 0;
		var i;
		for (i = 0; i < chunks.length; i++) edges += chunks[i].links.length;
		return edges / 2 - (chunks.length - 1);
	}

	function selfCheck() {
		var v;
		for (v = 0; v < 3; v++) {
			var seed;
			for (seed = 1; seed <= 6; seed++) {
				var map = generate({ seed: seed * 23 + v * 9, length: 8, verticality: v / 2 });
				if (componentCount(map) !== 1) throw new Error("地图不连通 " + map.seed);
				if (map.chunks.length < 8) throw new Error("房间太少 " + map.seed);
				if (!gapOk(map.chunks)) throw new Error("房间叠在一起 " + map.seed);
				var c;
				for (c = 0; c < map.chunks.length; c++) {
					if (map.chunks[c].role === "corridor" && Math.min(map.chunks[c].w, map.chunks[c].h) !== STROKE) throw new Error("走廊粗细不对");
				}
				var id = map.chunks[map.chunks.length - 1].id;
				var next = redraw(map, [id]);
				if (componentCount(next) !== 1) throw new Error("重绘后不连通");
				if (cycleCount(map) < 1 && v > 0) throw new Error("没有回路 " + map.seed);
			}
		}
		var h;
		for (h = 0; h < 8; h++) {
			var hut = generate({ seed: 100 + h * 17, length: 6 + (h % 5), verticality: (h % 5) / 4, layout: "hut" });
			if (hut.layout !== "hut") throw new Error("小屋地形标记丢失");
			if (componentCount(hut) !== 1) throw new Error("小屋不连通 " + hut.seed);
			if (!gapOk(hut.chunks)) throw new Error("小屋重叠 " + hut.seed);
			if (hut.chunks.length < 8) throw new Error("小屋太简单 " + hut.seed);
			var doors = 0;
			var roomCount = 0;
			var c;
			for (c = 0; c < hut.chunks.length; c++) {
				if (hut.chunks[c].role === "door") doors += 1;
				if (hut.chunks[c].role === "room") roomCount += 1;
			}
			if (doors < 3 || roomCount < 4) throw new Error("小屋结构不足 " + hut.seed);
			var again = redraw(hut, [hut.chunks[0].id]);
			if (componentCount(again) !== 1) throw new Error("小屋重绘后不连通");
		}
		var t;
		for (t = 0; t < 8; t++) {
			var tower = generate({ seed: 400 + t * 19, length: 5 + (t % 8), verticality: (t % 5) / 4, layout: "tower" });
			if (tower.layout !== "tower") throw new Error("高塔地形标记丢失");
			if (componentCount(tower) !== 1) throw new Error("高塔不连通 " + tower.seed);
			if (tower.height < tower.width * 1.15) throw new Error("高塔不够高 " + tower.seed);
			if (!gapOk(tower.chunks)) throw new Error("高塔重叠 " + tower.seed);
			var roomsOnly = [];
			var c;
			for (c = 0; c < tower.chunks.length; c++) if (tower.chunks[c].role === "room") roomsOnly.push(tower.chunks[c]);
			if (roomsOnly.length < 7) throw new Error("高塔房间太少 " + tower.seed);
			var beside = 0;
			var a;
			var b;
			var minW = 999;
			var maxW = 0;
			for (a = 0; a < roomsOnly.length; a++) {
				if (roomsOnly[a].w < minW) minW = roomsOnly[a].w;
				if (roomsOnly[a].w > maxW) maxW = roomsOnly[a].w;
				for (b = a + 1; b < roomsOnly.length; b++) {
					if (spanY(roomsOnly[a], roomsOnly[b]) >= 8 && spanX(roomsOnly[a], roomsOnly[b]) <= 0) beside += 1;
				}
			}
			if (beside < 2) throw new Error("高塔没有纵向分支 " + tower.seed);
			if (maxW - minW < 8) throw new Error("高塔房间太整齐 " + tower.seed);
			var moved = redraw(tower, [roomsOnly[1].id]);
			if (componentCount(moved) !== 1) throw new Error("高塔重绘后不连通");
			if (!gapOk(moved.chunks)) throw new Error("高塔重绘后重叠");
		}
		return "MAPGEN_OK";
	}

	root.MapWhitebox = {
		generate: generate,
		redraw: redraw,
		exportData: exportData,
		componentCount: componentCount,
		selfCheck: selfCheck,
	};
})(typeof window !== "undefined" ? window : globalThis);
