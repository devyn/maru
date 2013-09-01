var event_source;

var tasks = {};

var selected_task_id = null
  , created_task_id  = null;

function insert_tag_class_text(tag_name, class_name, text, destination) {
  var el = document.createElement(tag_name);
  el.className = class_name;

  if (text) el.appendChild(document.createTextNode(text));

  $(destination).append(el);
  return el;
}

function insert_div_class_text(class_name, text, destination) {
  return insert_tag_class_text("div", class_name, text, destination);
}

function ease_in(el) {
  $(el).css({
    transition: "opacity ease 0.5s, height ease 0.5s, padding ease 0.5s",
    height:     0,
    padding:    0,
    opacity:    0
  });

  setTimeout(function () {
    $(el).css({
      height:  "",
      padding: "",
      opacity: 1
    });

    setTimeout(function () {
      $(el).css({
        transition: "",
        opacity: ""
      });
    }, 500);
  }, 0);
}

function ease_out(el, callback) {
  $(el).css({
    transition: "opacity ease 0.5s, height ease 0.5s, padding ease 0.5s",
    height:     "",
    padding:    "",
    opacity:    1
  });

  setTimeout(function () {
    $(el).css({
      height:  0,
      padding: 0,
      opacity: 0
    });

    setTimeout(function () {
      if (typeof callback === 'function')
        callback(el);
    }, 500);
  }, 0);
}

function create_task_element(task) {
  task.element = document.createElement("li");

  insert_div_class_text("task_name", task.name, task.element);
  insert_div_class_text("task_speed", "", task.element);
  insert_div_class_text("clear_both", null, task.element);

  update_task_speed(task);

  var progress_bar  = insert_div_class_text("progress_bar", null, task.element);
  var progress_fill = insert_div_class_text("progress_fill", null, progress_bar);

  if (task.total_jobs !== null) {
    var percent = task.submitted_jobs / task.total_jobs * 100;

    progress_fill.style.width = percent.toString() + "%";

    insert_div_class_text("progress_text",
        "" + task.submitted_jobs + "/" + task.total_jobs +
          " completed (" + percent.toFixed(2) + "%)",
        progress_bar);
  } else {
    progress_fill.style.width = 0;

    insert_div_class_text("progress_text",
        "" + task.submitted_jobs + " completed",
        progress_bar);
  }

  $(task.element).click(function () {
    select_task(task);
  });

  $("#tasks").prepend(task.element);
}

function update_task_speed(task) {
  var nearest_job  = task.recent_jobs[0]
    , farthest_job = task.recent_jobs[task.recent_jobs.length - 1];

  if (nearest_job && farthest_job) {
    var farthest_time = Date.parse(farthest_job.submitted_at)
      , speed = 1000 / ((Date.now() - farthest_time) / task.recent_jobs.length) * 60 * 60;

    $(".task_speed", task.element).text(speed.toFixed(2) + " jobs/h");
  }
}

function select_task(task) {
  if (selected_task_id !== task.id) {
    if (selected_task_id !== null) {
      $(tasks[selected_task_id].element).removeClass('selected');
    }

    selected_task_id = task.id;

    $(task.element).addClass('selected');
  } else {
    $(task.element).removeClass('selected');

    selected_task_id = null;
  }

  show_details();
}

function show_details() {
  $("#details").empty();

  if (selected_task_id !== null) {
    var task = tasks[selected_task_id];

    insert_tag_class_text("h1", "", task.name, $("#details"));

    if (localStorage["task_secret_info:" + selected_task_id]) {
      var info = JSON.parse(localStorage["task_secret_info:" + selected_task_id]);

      insert_tag_class_text("code", "submit_to", info.submit_to, $("#details"));
    }

    var jobs = insert_tag_class_text("ul", "", null, $("#details"));
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

  $("#jobs").prepend(job_el);

  return job_el;
}

function tasks_reload(e) {
  var data = JSON.parse(e.data);

  $("#tasks").empty();

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
      $(task.element).addClass("selected");
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

  if (created_task_id === task.id) {
    console.log(['created_task_id', task.id]);
    setTimeout(function () {
      select_task(task);
    }, 0);
  }
}

function tasks_jobsubmitted(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.task_id];

  delete data.task_id;

  // reorder
  $("#tasks").prepend(task.element);

  task.submitted_jobs++;

  if (task.recent_jobs.length >= 10) {
    task.recent_jobs.pop();

    if (selected_task_id === task.id) {
      ease_out($("#jobs > *:last-child"), function (el) {
        el.remove();
      });
    }
  }

  task.recent_jobs.unshift(data);

  update_task_speed(task);

  if (selected_task_id === task.id) {
    var job_el = prepend_job_element(data);

    ease_in(job_el);
  }

  $(task.element).addClass("flash");

  if (task.total_jobs !== null) {
    var percent = task.submitted_jobs / task.total_jobs * 100;

    setTimeout(function () {
      $('.progress_fill', task.element).css('width', percent.toString() + "%");
    }, 10);

    $('.progress_text', task.element).text( 
        "" + task.submitted_jobs + "/" + task.total_jobs +
          " completed (" + percent.toFixed(2) + "%)");
  } else {
    $('.progress_text', task.element).text(
        "" + task.submitted_jobs + " completed");
  }

  setTimeout(function () {
    $(task.element).removeClass("flash");
  }, 0);
}

$(function() {
  // establish event source
  event_source = new EventSource("/tasks.event-stream");

  event_source.addEventListener("reload",       tasks_reload);
  event_source.addEventListener("taskcreated",  tasks_taskcreated);
  event_source.addEventListener("jobsubmitted", tasks_jobsubmitted);

  // register actions
  $(document).click(function() {
    $(".callout_popup").removeClass("show");
    setTimeout(function () {
      $(".callout_popup").css({display: ''});
    }, 400);
  });
  $(".callout_popup").click(function (e) {
    e.stopPropagation();
  });

  $("#new_task_link").click(function (e) {
    $("#new_task").css({display: 'block'});
    $("#new_task input[name='name']").val("").focus();
    $("#new_task input[name='total_jobs']").val("");

    setTimeout(function () {
      $("#new_task").addClass("show");
    }, 0);

    e.stopPropagation();
  });
  $("#new_task form").submit(function (e) {
    e.preventDefault();

    $.post('/tasks', $(this).serialize(), function (response) {
      localStorage["task_secret_info:" + response.id] = JSON.stringify(response);

      if (tasks.hasOwnProperty(response.id)) {
        select_task(tasks[response.id]);
      } else {
        created_task_id = response.id;
      }

      $("#new_task").removeClass("show");
      setTimeout(function () {
        $("#new_task").css({display: ''})
      }, 400);
    });
  });
});
