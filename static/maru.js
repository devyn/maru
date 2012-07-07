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
		setDetails(el.id.replace(/^group-/, ''), function () {
			el.className = 'group selected';
		});
	}
}

function setDetails(group, onsuccess) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function() {
		if (req.readyState === 4) {
			if (req.status === 200) {
				if (typeof onsuccess === 'function') onsuccess();
				details.innerHTML = req.response;
			} else {
				details.innerHTML = "";
			}
		}
	};

	req.open('GET', "/group/"+group+"/details");
	req.send(null);
}

function setGroupOnclicks() {
	var groups = document.getElementsByClassName("group");

	for (var i = 0; i < groups.length; i++) {
		groups[i].onclick = function () {selectJob(this)};
	}
}

function subscribeGroups() {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 200) {
				if (!req.responseText) return subscribeGroups();

				var message = JSON.parse(req.responseText);

				switch (message.type) {
					case "groupStatus":
						var groupEl      = document.getElementById("group-" + message.groupID)
							, completeEl   = groupEl.querySelector(".progress .complete")
							, processingEl = groupEl.querySelector(".progress .processing")
							;

						completeEl.style.width = (message.complete/message.total*100).toString() + "%";
						processingEl.style.width = (message.processing/message.total*100).toString() + "%";

						if (groupEl.className.match(/\bselected\b/i)) {
							setDetails(message.groupID);
						}
						break;
				}

				subscribeGroups();
			} else {
				setTimeout(subscribeGroups, 3000);
			}
		}
	};

	req.open("GET", "/subscribe");
	req.send(null);
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

	el.style.animation = type + " 1s";
	el.style.mozAnimation = type + " 1s";
	el.style.webkitAnimation = type + " 1s";
	el.style.oAnimation = type + " 1s";
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

function addWorker(formEl) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 200) {
				var res = JSON.parse(req.responseText)["worker"];

				var worker = document.createElement("li")
				  , name   = document.createElement("div")
				  , key    = document.createElement("div")
				  , nav    = document.createElement("nav")
				  , ul     = document.createElement("ul")
				  , li1    = document.createElement("li")
				  , li2    = document.createElement("li")
				  , a1     = document.createElement("a")
				  , a2     = document.createElement("a")
				  ;

				name.className = "name";
				name.appendChild(document.createTextNode(res["name"]));
				worker.appendChild(name);

				key.className = "key";
				key.appendChild(document.createTextNode(res["authenticator"]));
				worker.appendChild(key);

				a1.appendChild(document.createTextNode("regenerate key"));
				a1.onclick = regenerateKeyForWorker.bind(a2, res["id"], a2);
				li1.appendChild(a1);
				ul.appendChild(li1);

				a2.appendChild(document.createTextNode("delete"));
				a2.onclick = deleteWorker.bind(a2, res["id"], a2);
				li2.appendChild(a2);
				ul.appendChild(li2);

				nav.appendChild(ul);
				worker.appendChild(nav);

				worker.id = "worker-" + res["id"];

				var workersItemAdd = document.getElementById("workers-item-add");
				workersItemAdd.parentNode.insertBefore(worker, workersItemAdd);

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

	req.open("POST", "/worker/new");
	req.send(new FormData(formEl));
}

function regenerateKeyForWorker(worker, flashTarget) {
	var req      = new XMLHttpRequest()
	  , workerEl = document.getElementById("worker-" + worker)
	  ;

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 200) {
				var res = JSON.parse(req.responseText)["worker"];
				workerEl.getElementsByClassName("key")[0].textContent = res["authenticator"];

				if (flashTarget) flash(flashTarget, "flash-text-success");
			} else {
				if (flashTarget) flash(flashTarget, "flash-text-error");
			}
		}
	};

	req.open("POST", "/worker/" + worker + "/key/regenerate");
	req.send(null);
}

function deleteWorker(worker, flashTarget) {
	var req      = new XMLHttpRequest()
	  , workerEl = document.getElementById("worker-" + worker)
	  ;

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 204) {
				workerEl.parentNode.removeChild(workerEl);
			} else {
				if (flashTarget) flash(flashTarget, "flash-text-error");
			}
		}
	};

	req.open("POST", "/worker/" + worker + "/delete");
	req.send(null);
}

function logUserOut(user, flashTarget) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 204) {
				if (flashTarget) flash(flashTarget, "flash-text-success");
			} else {
				if (flashTarget) flash(flashTarget, "flash-text-error");
			}
		}
	};

	req.open("POST", "/user/" + user + "/logout");
	req.send(null);
}

function createUser(formEl) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 200) {
				var res = JSON.parse(req.responseText)["user"];

				var inputs = formEl.querySelectorAll("input:not([type='submit'])");
				for (var i = 0; i < inputs.length; i++) inputs[i].value = "";

				var user  = document.createElement("li")
				  , email = document.createElement("div")
				  , nav   = document.createElement("nav")
				  , ul    = document.createElement("ul")
				  , li1   = document.createElement("li")
				  , li2   = document.createElement("li")
				  , li3   = document.createElement("li")
				  , a1    = document.createElement("a")
				  , a2    = document.createElement("a")
				  , a3    = document.createElement("a")
				  ;

				user.className = "user";
				user.id = "user-" + res["id"];

				email.className = "email";
				email.appendChild(document.createTextNode(res["email"]));
				user.appendChild(email);

				a1.href = "/user/" + res["id"] + "/login";
				a1.appendChild(document.createTextNode("log in"));
				li1.appendChild(a1);
				ul.appendChild(li1);

				a2.href = "/user/" + res["id"] + "/preferences";
				a2.appendChild(document.createTextNode("edit"));
				li2.appendChild(a2);
				ul.appendChild(li2);

				a3.onclick = deleteUser.bind(null, res["id"], adminRemoveUser, a3);
				a3.appendChild(document.createTextNode("delete"));
				li3.appendChild(a3);
				ul.appendChild(li3);

				nav.appendChild(ul);
				user.appendChild(nav);

				document.getElementById("users").insertBefore(user, document.getElementById("users-add-item"));

				flash(formEl.querySelector("input[type='submit']"), "flash-box-success");
			} else {
				flash(formEl.querySelector("input[type='submit']"), "flash-box-error");
			}
		}
	};

	req.open("POST", "/user/new");
	req.send(new FormData(formEl));
}

function setPermission(user, permission, checkbox) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status != 204) {
				checkbox.checked = !checkbox.checked;
				flash(checkbox, "flash-box-error");
			}
		}
	};

	req.open("PUT", "/user/" + user + "/permission/" + permission);
	req.send(checkbox.checked ? "true" : "false");
}

function deleteUser(user, userIsMe, flashTarget) {
	if (!confirm("Are you sure? This action is irreversable.")) return;

	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 204) {
				if (typeof userIsMe === "function") {
					userIsMe(user, flashTarget);
				} else {
					window.location = userIsMe ? "/" : "/admin";
				}
			} else {
				if (flashTarget) flash(flashTarget, "flash-text-error");
			}
		}
	};

	req.open("POST", "/user/" + user + "/delete");
	req.send(null);
}

function adminRemoveUser(user, flashTarget) {
	var userEl = document.getElementById("user-" + user);
	userEl.parentNode.removeChild(userEl);
}

window.addEventListener('load', function () {
	setGroupOnclicks();

	var error = document.getElementById("error");
	if (error) {
		error.onclick = hideError;
	}
});
