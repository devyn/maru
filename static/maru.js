function selectGroup(el) {
	var curSel = document.querySelector(".group.selected");
	if (curSel && curSel.id !== el.id) {
		curSel.className = 'group';
	}

	var details = document.getElementById("details");

	if (el.className.match(/selected/)) {
		el.className = el.className.replace(/ *selected/, '');
		details.innerHTML = "";
	} else {
		setDetails(el.id.replace(/^group-/, ''), function () {
			el.className += ' selected';
		});
	}
}

function pauseGroup(group) {
	var el = document.getElementById("group-" + group);

	if (!el.className.match(/paused/)) {
		var req = new XMLHttpRequest();

		req.onreadystatechange = function () {
			if (req.readyState === 4 && req.status === 204) {
				el.className += ' paused';
			}
		};

		req.open("POST", "/group/" + group + "/pause");
		req.send(null);
	}
}

function resumeGroup(group) {
	var el = document.getElementById("group-" + group);

	if (el.className.match(/paused/)) {
		var req = new XMLHttpRequest();

		req.onreadystatechange = function () {
			if (req.readyState === 4 && req.status === 204) {
				el.className = el.className.replace(/ *paused/, '');
			}
		};

		req.open("POST", "/group/" + group + "/resume");
		req.send(null);
	}
}

function deleteGroup(group) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState === 4 && req.status === 204) {
			var groupEl = document.getElementById("group-" + group);

			if (groupEl && groupEl.parentNode) groupEl.parentNode.removeChild(groupEl);
		}
	};

	req.open('DELETE', "/group/"+group);
	req.send(null);
}

function setDetails(group, onsuccess) {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState === 4) {
			var details = document.getElementById("details");

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

function subscribeGroups() {
	if (typeof EventSource !== "undefined") {
		subscribeGroupsViaEventStream();
	} else if (typeof XMLHttpRequest !== "undefined") {
		longPollGroups();
	}
}

function subscribeGroupsViaEventStream() {
	var source = new EventSource("/subscribe.event-stream");

	source.onmessage = function (event) {
		try {
			processSubMessage(JSON.parse(event.data));
		} catch (e) {
			console.log(e);
		}
	};

	return source;
}

function longPollGroups() {
	var req = new XMLHttpRequest();

	req.onreadystatechange = function () {
		if (req.readyState == 4) {
			if (req.status == 200) {
				try {
					var rs = req.responseText.replace(/\0/g, '');

					if (!rs) return subscribeGroups();

					var message = JSON.parse(rs);

					processSubMessage(message);
				} finally {
					longPollGroups();
				}
			} else {
				setTimeout(longPollGroups, 3000);
			}
		}
	};

	req.open("GET", "/subscribe.poll");
	req.send(null);
}

function processSubMessage(message) {
	if (message.type === "groupStatus") {
		var groupEl      = document.getElementById("group-" + message.groupID)
		  , completeEl   = groupEl.querySelector(".progress .complete")
		  , processingEl = groupEl.querySelector(".progress .processing")
		  ;

		completeEl.style.width = (message.complete/message.total*100).toString() + "%";
		processingEl.style.width = (message.processing.length/message.total*100).toString() + "%";

		if (groupEl.className.match(/\bselected\b/i)) {
			var details     = document.querySelector("#details")
			  , nComplete   = details.querySelector("#status .complete")
			  , nProcessing = details.querySelector("#status .processing")
			  , nRemaining  = details.querySelector("#status .remaining")
				, eTimeLeft   = details.querySelector("#status .estimated-time-left")
			  , lProcessing = details.querySelector("#processing-jobs tbody")
			  ;

			nComplete.textContent   = message.complete;
			nProcessing.textContent = message.processing.length;
			nRemaining.textContent  = message.total - message.complete - message.processing.length;
			eTimeLeft.textContent   = message.estimatedTimeLeft;

			while (lProcessing.hasChildNodes()) lProcessing.removeChild(lProcessing.lastChild);

			for (var i = 0; i < message.processing.length; i++) {
				var tr       = document.createElement("tr")
				  , tdName   = document.createElement("td")
				  , tdWorker = document.createElement("td")
				  ;

				tdName.appendChild(document.createTextNode(message.processing[i].name));
				tr.appendChild(tdName);

				tdWorker.appendChild(document.createTextNode(message.processing[i].worker));
				tr.appendChild(tdWorker);

				lProcessing.appendChild(tr);
			}
		}
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
		el.style.MozAnimation = "";
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
	el.style.MozAnimation = type + " 1s";
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

	req.open("DELETE", "/worker/" + worker);
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
				  , perms = document.createElement("div")
				  , perm1 = document.createElement("input")
				  , perm2 = document.createElement("input")
				  , perm3 = document.createElement("input")
				  , perl1 = document.createElement("label")
				  , perl2 = document.createElement("label")
				  , perl3 = document.createElement("label")
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

				perm1.type = "checkbox";
				perm1.onchange = function () { setPermission(res["id"], "can_own_workers", this); };
				perl1.appendChild(perm1);
				perl1.appendChild(document.createTextNode(" Can own workers"));
				perms.appendChild(perl1);

				perm2.type = "checkbox";
				perm2.onchange = function () { setPermission(res["id"], "can_own_users", this); };
				perl2.appendChild(perm2);
				perl2.appendChild(document.createTextNode(" Can own users"));
				perms.appendChild(perl2);

				perm3.type = "checkbox";
				perm3.onchange = function () { setPermission(res["id"], "is_admin", this); };
				perl3.appendChild(perm3);
				perl3.appendChild(document.createTextNode(" Is admin"));
				perms.appendChild(perl3);

				perms.className = "permissions";
				user.appendChild(perms);

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

	req.open("DELETE", "/user/" + user);
	req.send(null);
}

function adminRemoveUser(user, flashTarget) {
	var userEl = document.getElementById("user-" + user);
	userEl.parentNode.removeChild(userEl);
}

function setGroupNewFormKind(kind) {
	var groupNewFormBody   = document.getElementById("group-new-form-body")
	  , groupNewFormSubmit = document.getElementById("group-new-form-submit")
	  ;

	groupNewFormBody.innerHTML = "";
	groupNewFormSubmit.disabled = "disabled";

	if (kind !== "") {
		var req = new XMLHttpRequest();

		req.onreadystatechange = function () {
			if (req.readyState == 4 && req.status == 200) {
				var split        = req.responseText.split('\0')
				  , restrictions = JSON.parse(split.splice(0, 1))
				  ;

				groupNewFormBody.innerHTML = split.join('\0');
				groupNewFormSubmit.disabled = null;

				restrictGroupNewForm(restrictions);
			}
		};

		req.open("GET", "/group/new/form/" + kind);
		req.send(null);
	}
}

function restrictGroupNewForm(restrictions) {
	for (var i = 0; i < restrictions.length; i++) {
	}
}

function validateGroupNewForm(flash) {
}

function addToGroupNewFormList(triggerEl) {
	var list = triggerEl.parentNode.parentNode;

	var li     = document.createElement("li")
	  , input  = document.createElement("input")
	  , remove = document.createElement("a")
	  ;

	if (list.className.match(/passwords/)) {
		input.type = "password";
	} else if (list.className.match(/files/)) {
		input.type = "file";
	}

	var md = list.className.match(/(string|file|password|url|number|integer)s/);

	if (md) {
		input.className = md[1];
	}

	var last = triggerEl.parentNode.previousSibling;

	if (last) {
		input.name = last.getElementsByTagName("input")[0].name.replace(/\[(\d+)\]$/, function (_, n) { return '[' + (parseInt(n,10)+1) + ']'; });
	} else {
		input.name = list.id.replace(/^field-/, '').replace(/-([^-]*)/g, '[$1]') + '[0]';
	}

	input.id = 'field-' + input.name.replace(/\[([^\]]*)\]/g, '-$1');

	remove.onclick = function () { removeFromGroupNewFormList(this) };

	remove.appendChild(document.createTextNode("remove"));

	li.appendChild(input);
	li.appendChild(document.createTextNode(" "));
	li.appendChild(remove);

	list.insertBefore(li, triggerEl.parentNode);
}

function removeFromGroupNewFormList(triggerEl) {
	// NOTE: this will leave gaps in the indices, but it shouldn't matter.
	triggerEl.parentNode.parentNode.removeChild(triggerEl.parentNode);
}

window.addEventListener('load', function () {
	var error = document.getElementById("error");
	if (error) {
		error.onclick = hideError;
	}
});
