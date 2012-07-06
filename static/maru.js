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
		groups[i].onclick = function () {selectJob(this)};
	}
}

function hideError() {
	this.style.opacity = 0;
	this.addEventListener('transitionend',       function () { this.style.display = 'none'; }, true);
	this.addEventListener('webkitTransitionEnd', function () { this.style.display = 'none'; }, true);
	this.addEventListener('oTransitionEnd',      function () { this.style.display = 'none'; }, true);
}

function flash(el, type) {
	var animationend = function () {
		el.style.animation = "";
		el.style.mozAnimation = "";
		el.style.webkitAnimation = "";
		el.style.oAnimation = "";

		el.removeEventListener('animationend', arguments.callee, true);
		el.removeEventListener('webkitAnimationEnd', arguments.callee, true);
		el.removeEventListener('oAnimationEnd', arguments.callee, true);
	};

	el.addEventListener('animationend', animationend, true);
	el.addEventListener('webkitAnimationEnd', animationend, true);
	el.addEventListener('oAnimationEnd', animationend, true);

	el.style.animation = type + " 3s";
	el.style.mozAnimation = type + " 3s";
	el.style.webkitAnimation = type + " 3s";
	el.style.oAnimation = type + " 3s";
}

function changePassword(user, formEl) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 200) {
				var inputs = formEl.querySelectorAll("input:not([type='submit'])");
				for (var i = 0; i < inputs.length; i++) {
					inputs[i].value = "";
				}

				flash(formEl.querySelector("input[type='submit']"), "flash-box-success");
			} else {
				flash(formEl.querySelector("input[type='submit']"), "flash-box-error");
			}
		}
	};

	req.open("POST", "/user/" + user + "/password");
	req.send(new FormData(formEl));
}

window.addEventListener('load', function () {
	setGroupOnclicks();

	var error = document.getElementById("error");
	if (error) {
		error.onclick = hideError;
	}
});
