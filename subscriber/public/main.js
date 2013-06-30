var $ = function (element_name) {
  return document.getElementById(element_name);
};

function clear_children(el) {
  while (el.hasChildNodes()) el.removeChild(el.lastChild);
}

var event_source;

var tasks = {};

var selected_task_id = null;

function insert_tag_class_text(tag_name, class_name, text, destination) {
  var el = document.createElement(tag_name);
  el.className = class_name;

  if (text) el.appendChild(document.createTextNode(text));

  destination.appendChild(el);
  return el;
}

function insert_div_class_text(class_name, text, destination) {
  return insert_tag_class_text("div", class_name, text, destination);
}

function ease_in(el) {
  el.style.transition = "opacity ease 0.5s, height ease 0.5s, padding ease 0.5s";
  el.style.height     = "0";
  el.style.padding    = "0";
  el.style.opacity    = "0.0";

  setTimeout(function () {
    el.style.height  = null;
    el.style.padding = null;
    el.style.opacity = "1.0";

    setTimeout(function () {
      el.style.transition = null;
      el.style.opacity = null;
    }, 500);
  }, 0);
}

function ease_out(el) {
  el.style.transition = "opacity ease 0.5s, height ease 0.5s, padding ease 0.5s";
  el.style.height     = null;
  el.style.padding    = null;
  el.style.opacity    = "1.0";

  setTimeout(function () {
    el.style.height  = "0";
    el.style.padding = "0";
    el.style.opacity = "0.0";

    setTimeout(function () {
      el.parentNode.removeChild(el);
    }, 500);
  }, 0);
}

function create_task_element(task) {
  task.element = document.createElement("li");

  insert_div_class_text("task_name", task.name, task.element);
  insert_div_class_text("task_speed", "", task.element);
  insert_div_class_text("clear_both", null, task.element);

  var progress_bar  = insert_div_class_text("progress_bar", null, task.element);
  var progress_fill = insert_div_class_text("progress_fill", null, progress_bar);

  if (task.total_jobs !== null) {
    var percent = task.submitted_jobs / task.total_jobs * 100;

    progress_fill.style.width = percent.toString() + "%";

    insert_div_class_text("progress_text", "" + task.submitted_jobs + "/" + task.total_jobs + " completed (" + percent.toFixed(2) + "%)", progress_bar);
  } else {
    progress_fill.style.width = 0;

    insert_div_class_text("progress_text", "" + task.submitted_jobs + " completed", progress_bar);
  }

  task.element.addEventListener("click", function () {
    select_task(task);
  });

  $("tasks").insertBefore(task.element, $("tasks").firstChild);
}

function select_task(task) {
  if (selected_task_id !== task.id) {
    if (selected_task_id !== null) {
      var el = tasks[selected_task_id].element;
      
      el.className = el.className.replace(/ *selected */g, "");
    }

    selected_task_id = task.id;

    task.element.className += " selected";
  } else {
    var el = task.element;

    el.className = el.className.replace(/ *selected */g, "");

    selected_task_id = null;
  }

  show_details();
}

function show_details() {
  clear_children($("details"));

  if (selected_task_id !== null) {
    var task = tasks[selected_task_id];

    insert_tag_class_text("h1", "", task.name, $("details"));

    var jobs = insert_tag_class_text("ul", "", null, $("details"));
    jobs.id = "jobs";

    for (var i = task.recent_jobs.length - 1; i >= 0; i--) {
      var job = task.recent_jobs[i];

      prepend_job_element(job);
    }
  }
}

function prepend_job_element(job) {
  var job_el = document.createElement("li");

  var left_group = insert_div_class_text("job_left_group", null, job_el);

  if (job.name === null) {
    insert_div_class_text("job_name unnamed", "<unnamed>", left_group);
  } else {
    insert_div_class_text("job_name", job.name, left_group);
  }

  insert_div_class_text("job_worker", job.worker, left_group);

  var right_group = insert_div_class_text("job_right_group", null, job_el);

  var type = job.type ? job.type.split(".") : [];

  var type_el = insert_div_class_text("job_type", null, right_group);

  if (type.length > 1) {
    insert_tag_class_text("span", "namespace", type.slice(0, type.length - 1).join(".") + ".", type_el);
  }

  if (type.length > 0) {
    type_el.appendChild(document.createTextNode(type[type.length - 1]));
  }

  insert_div_class_text("job_submitted_at", job.submitted_at, right_group);

  $("jobs").insertBefore(job_el, $("jobs").firstChild);

  return job_el;
}

function tasks_reload(e) {
  var data = JSON.parse(e.data);

  clear_children($("tasks"));

  tasks = {};

  for (var i = 0; i < data.length; i++) {
    var task = tasks[data[i].id] = {};

    task.id   = data[i].id;
    task.name = data[i].name;

    task.total_jobs     = data[i].total_jobs;
    task.submitted_jobs = data[i].submitted_jobs;
    task.recent_jobs    = data[i].recent_jobs;

    create_task_element(task);

    if (selected_task_id === task.id) {
      task.className = "selected";
    }
  }

  if (!tasks.hasOwnProperty(selected_task_id)) {
    selected_task_id = null;
  }

  show_details();
}

function tasks_taskcreated(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.id] = {};

  task.id   = data.id;
  task.name = data.name;

  task.total_jobs     = data.total_jobs;
  task.submitted_jobs = 0;
  task.recent_jobs    = [];

  create_task_element(task);
}

function tasks_jobsubmitted(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.task_id];

  delete data.task_id;

  // reorder
  task.element.parentNode.removeChild(task.element);
  $("tasks").insertBefore(task.element, $("tasks").firstChild);

  task.submitted_jobs++;

  if (task.recent_jobs.length >= 10) {
    task.recent_jobs.pop();

    if (selected_task_id === task.id) {
      ease_out($("jobs").children[9]);
    }
  }

  task.recent_jobs.unshift(data);

  if (selected_task_id === task.id) {
    var job_el = prepend_job_element(data);

    ease_in(job_el);
  }

  task.element.className += " flash";

  if (task.total_jobs !== null) {
    var percent = task.submitted_jobs / task.total_jobs * 100;

    setTimeout(function () {
      task.element.getElementsByClassName("progress_fill")[0].style.width = percent.toString() + "%";
    }, 0); // next tick

    task.element.getElementsByClassName("progress_text")[0].textContent = 
      "" + task.submitted_jobs + "/" + task.total_jobs + " completed (" + percent.toFixed(2) + "%)";
  } else {
    task.element.getElementsByClassName("progress_text")[0].textContent =
      "" + task.submitted_jobs + " completed";
  }

  setTimeout(function () {
    task.element.className = task.element.className.replace(/ *flash */g, "");
  }, 0);
}

window.addEventListener("load", function () {
  // establish event source
  event_source = new EventSource("/tasks.event-stream");

  event_source.addEventListener("reload",       tasks_reload);
  event_source.addEventListener("taskcreated",  tasks_taskcreated);
  event_source.addEventListener("jobsubmitted", tasks_jobsubmitted);
});
