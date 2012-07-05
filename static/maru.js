function selectJob(el) {
	var curSel = document.querySelector(".group.selected");
	if (curSel && curSel.id !== el.id) {
		curSel.className = 'group';
	}

	var details = document.getElementById("details");

	if (el.className.match(/selected/)) {
		el.className = 'group';
		details.innerHTML = "";
	} else {
		var req = new XMLHttpRequest();
		req.onreadystatechange = function() {
			if (req.readyState === 4) {
				if (req.status === 200) {
					el.className = 'group selected';
					details.innerHTML = req.response;
				} else {
					details.innerHTML = "";
				}
			}
		};
		req.open('GET', "/group/"+el.id.replace(/^group-/, '')+"/details");
		req.send(null);
	}
}

function setGroupOnclicks() {
	var groups = document.getElementsByClassName("group");

	for (var i = 0; i < groups.length; i++) {
		groups[i].onclick = function() {selectJob(this)};
	}
}

window.addEventListener('load', function() {
	setGroupOnclicks();
});
