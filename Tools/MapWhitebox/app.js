(function () {
	var DRAW = 8;
	var SCALE = 2;
	var PAD = 28;
	var BANNER = 64;
	var canvas = document.getElementById("map");
	var ctx = canvas.getContext("2d");
	var map = null;
	var selected = {};
	var undoStack = [];
	var drag = null;

	function numberValue(id, fallback) {
		var value = Number(document.getElementById(id).value);
		return Number.isFinite(value) ? value : fallback;
	}

	function optionsFromForm() {
		var layout = document.getElementById("layout").value;
		if (layout !== "road" && layout !== "hut" && layout !== "tower") layout = "tower";
		return {
			seed: Math.max(1, Math.floor(numberValue("seed", 1))),
			length: Math.max(5, Math.min(12, Math.floor(numberValue("length", 8)))),
			verticality: numberValue("verticality", 35) / 100,
			layout: layout,
		};
	}

	function applyLayoutLabels() {
		var layout = document.getElementById("layout").value;
		var lengthLabel = "主路房间";
		var left = "更横向";
		var right = "更纵向";
		if (layout === "hut") {
			lengthLabel = "室内跨度";
			left = "层高较矮";
			right = "层高较高";
		} else if (layout === "tower") {
			lengthLabel = "攀爬层数";
			left = "路线更曲折";
			right = "竖井更长";
		}
		document.getElementById("length-label").textContent = lengthLabel;
		document.getElementById("vert-left").textContent = left;
		document.getElementById("vert-right").textContent = right;
	}

	function layoutSize() {
		return {
			w: PAD * 2 + map.width * DRAW,
			h: BANNER + 18 + map.height * DRAW,
		};
	}

	function resizeCanvas() {
		var size = layoutSize();
		canvas.width = size.w * SCALE;
		canvas.height = size.h * SCALE;
		canvas.style.width = size.w + "px";
		canvas.style.height = size.h + "px";
		ctx.setTransform(SCALE, 0, 0, SCALE, 0, 0);
	}

	function origin() {
		return { x: PAD, y: BANNER };
	}

	function cellFilled(x, y) {
		if (x < 0 || y < 0 || x >= map.width || y >= map.height) return false;
		return map.owners[y * map.width + x] !== 0;
	}

	function isEdge(x, y) {
		return !cellFilled(x - 1, y) || !cellFilled(x + 1, y) || !cellFilled(x, y - 1) || !cellFilled(x, y + 1);
	}

	function render() {
		var size = layoutSize();
		var spot = origin();
		resizeCanvas();
		ctx.fillStyle = "#1d2744";
		ctx.fillRect(0, 0, size.w, size.h);
		ctx.fillStyle = "#f4f1ea";
		ctx.font = "600 20px Segoe UI, Microsoft YaHei, sans-serif";
		ctx.fillText("PICTOUR 关卡白模", PAD, 28);
		ctx.font = "13px Segoe UI, Microsoft YaHei, sans-serif";
		ctx.fillStyle = "#c9d0ea";
		ctx.fillText("种子 " + map.seed + "    修订 " + map.revision, PAD, 50);
		var y;
		var x;
		for (y = 0; y < map.height; y++) {
			for (x = 0; x < map.width; x++) {
				if (!cellFilled(x, y)) continue;
				var owner = map.owners[y * map.width + x];
				ctx.fillStyle = selected[owner] ? "#e7c36a" : "#5b82f0";
				ctx.fillRect(spot.x + x * DRAW, spot.y + y * DRAW, DRAW, DRAW);
			}
		}
		ctx.beginPath();
		ctx.strokeStyle = "#f7f8ff";
		ctx.lineWidth = 2;
		for (y = 0; y < map.height; y++) {
			for (x = 0; x < map.width; x++) {
				if (!cellFilled(x, y)) continue;
				var left = spot.x + x * DRAW;
				var top = spot.y + y * DRAW;
				if (!cellFilled(x, y - 1)) {
					ctx.moveTo(left, top);
					ctx.lineTo(left + DRAW, top);
				}
				if (!cellFilled(x, y + 1)) {
					ctx.moveTo(left, top + DRAW);
					ctx.lineTo(left + DRAW, top + DRAW);
				}
				if (!cellFilled(x - 1, y)) {
					ctx.moveTo(left, top);
					ctx.lineTo(left, top + DRAW);
				}
				if (!cellFilled(x + 1, y)) {
					ctx.moveTo(left + DRAW, top);
					ctx.lineTo(left + DRAW, top + DRAW);
				}
			}
		}
		ctx.stroke();
		if (drag) {
			var rx = Math.min(drag.x, drag.cx);
			var ry = Math.min(drag.y, drag.cy);
			ctx.fillStyle = "rgba(242, 209, 90, 0.18)";
			ctx.strokeStyle = "#f2d15a";
			ctx.lineWidth = 1;
			ctx.fillRect(rx, ry, Math.abs(drag.cx - drag.x), Math.abs(drag.cy - drag.y));
			ctx.strokeRect(rx, ry, Math.abs(drag.cx - drag.x), Math.abs(drag.cy - drag.y));
		}
	}

	function selectedCount() {
		return Object.keys(selected).length;
	}

	function updateStatus(extra) {
		var text = "轮廓块 " + map.chunks.length + " 个，已选 " + selectedCount() + " 个。";
		if (extra) text += " " + extra;
		document.getElementById("status").textContent = text;
		var hasSelection = selectedCount() > 0;
		document.getElementById("redraw").disabled = !hasSelection;
		document.getElementById("undo").disabled = undoStack.length === 0;
	}

	function remember() {
		undoStack.push(JSON.stringify(map));
		if (undoStack.length > 20) undoStack.shift();
	}

	function generateFromForm() {
		var options = optionsFromForm();
		document.getElementById("seed").value = String(options.seed);
		document.getElementById("length").value = String(options.length);
		map = MapWhitebox.generate(options);
		selected = {};
		undoStack = [];
		render();
		updateStatus();
		location.hash = "seed=" + options.seed;
	}

	function canvasPoint(event) {
		var rect = canvas.getBoundingClientRect();
		return {
			x: ((event.clientX - rect.left) / rect.width) * layoutSize().w,
			y: ((event.clientY - rect.top) / rect.height) * layoutSize().h,
		};
	}

	function chunkAt(point) {
		var spot = origin();
		var x = Math.floor((point.x - spot.x) / DRAW);
		var y = Math.floor((point.y - spot.y) / DRAW);
		if (x < 0 || y < 0 || x >= map.width || y >= map.height) return 0;
		return map.owners[y * map.width + x];
	}

	function selectRect(a, b, additive) {
		if (!additive) selected = {};
		var spot = origin();
		var x0 = Math.floor((Math.min(a.x, b.x) - spot.x) / DRAW);
		var y0 = Math.floor((Math.min(a.y, b.y) - spot.y) / DRAW);
		var x1 = Math.floor((Math.max(a.x, b.x) - spot.x) / DRAW);
		var y1 = Math.floor((Math.max(a.y, b.y) - spot.y) / DRAW);
		var y;
		var x;
		for (y = y0; y <= y1; y++) {
			for (x = x0; x <= x1; x++) {
				if (x < 0 || y < 0 || x >= map.width || y >= map.height) continue;
				var id = map.owners[y * map.width + x];
				if (id) selected[id] = true;
			}
		}
	}

	function download(filename, blob) {
		var link = document.createElement("a");
		link.href = URL.createObjectURL(blob);
		link.download = filename;
		link.click();
		URL.revokeObjectURL(link.href);
	}

	function fileStem() {
		return "PICTOUR白模_" + map.seed + "_修订" + map.revision;
	}

	document.getElementById("layout").addEventListener("change", function () {
		applyLayoutLabels();
		generateFromForm();
	});
	document.getElementById("generate").addEventListener("click", generateFromForm);
	document.getElementById("random-seed").addEventListener("click", function () {
		document.getElementById("seed").value = String(1 + Math.floor(Math.random() * 999999));
		generateFromForm();
	});
	document.getElementById("redraw").addEventListener("click", function () {
		remember();
		var next = MapWhitebox.redraw(map, Object.keys(selected).map(Number));
		if (next === map) {
			undoStack.pop();
			updateStatus("这一块旁边没有空间重画，选区保持原样。");
			return;
		}
		map = next;
		render();
		updateStatus("选中的一段已重绘。");
	});
	document.getElementById("clear-selection").addEventListener("click", function () {
		selected = {};
		render();
		updateStatus();
	});
	document.getElementById("undo").addEventListener("click", function () {
		if (!undoStack.length) return;
		map = JSON.parse(undoStack.pop());
		render();
		updateStatus("已撤销。");
	});
	document.getElementById("download-png").addEventListener("click", function () {
		var previous = selected;
		selected = {};
		render();
		canvas.toBlob(function (blob) {
			download(fileStem() + ".png", blob);
			selected = previous;
			render();
		});
	});
	document.getElementById("download-json").addEventListener("click", function () {
		var payload = JSON.stringify(MapWhitebox.exportData(map), null, 2);
		download(fileStem() + ".json", new Blob([payload], { type: "application/json" }));
	});

	canvas.addEventListener("mousedown", function (event) {
		drag = canvasPoint(event);
		drag.cx = drag.x;
		drag.cy = drag.y;
		drag.shift = event.shiftKey;
	});
	window.addEventListener("mousemove", function (event) {
		if (!drag) return;
		var point = canvasPoint(event);
		drag.cx = point.x;
		drag.cy = point.y;
		render();
	});
	window.addEventListener("mouseup", function (event) {
		if (!drag) return;
		var end = canvasPoint(event);
		var moved = Math.abs(end.x - drag.x) + Math.abs(end.y - drag.y);
		if (moved < 6) {
			var hit = chunkAt(end);
			if (hit) {
				if (selected[hit]) delete selected[hit];
				else selected[hit] = true;
			}
		} else {
			selectRect(drag, end, event.shiftKey || drag.shift);
		}
		drag = null;
		render();
		updateStatus();
	});

	var hashSeed = /seed=(\d+)/.exec(location.hash);
	if (hashSeed) document.getElementById("seed").value = hashSeed[1];
	generateFromForm();
})();
