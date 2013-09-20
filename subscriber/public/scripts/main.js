var event_source;

var tasks = {};

var selected_task_id = null
  , created_task_id  = null;

var popup_window_transition_duration = 200; // msecs

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
    var nearest_time     = Date.parse(nearest_job.submitted_at)
      , farthest_time    = Date.parse(farthest_job.submitted_at);

    if (nearest_time === farthest_time) {

      $(".task_speed", task.element).empty();
    } else {

      var average_duration = (nearest_time - farthest_time) / task.recent_jobs.length
        , speed            = (1000 / average_duration) * 60 * 60;

      if (Date.now() > nearest_time + average_duration * 2) {
        // If double the average duration of a job has passed,
        // the job should be considered inactive.
        $(".task_speed", task.element).empty();
      } else {
        $(".task_speed", task.element).text(speed.toFixed(2) + " jobs/h");
      }
    }
  } else {
    $(".task_speed", task.element).empty();
  }
}

function update_progress(task) {
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

function task_secret_info(task_id) {
  if (localStorage["task_secret_info:" + task_id]) {
    return JSON.parse(localStorage["task_secret_info:" + task_id]);
  }
}

function show_details() {
  $("#details").empty();

  if (selected_task_id !== null) {
    var task = tasks[selected_task_id];

    insert_tag_class_text("h1", "", task.name, $("#details"));

    var action_menu = insert_tag_class_text("ul", "action_menu", null, $("#details"));

    var info;
    if (info = task_secret_info(selected_task_id)) {
      var menu_item = insert_tag_class_text("li", "", null, action_menu)
        , link      = insert_tag_class_text("a", "", "Produce jobs for this task", menu_item);

      $(link).click(task_produce_link);

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
      ease_out($("#jobs")[0].children[9], function (el) {
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

  update_progress(task);

  setTimeout(function () {
    $(task.element).removeClass("flash");
  }, 0);
}

function tasks_changetotal(e) {
  var data = JSON.parse(e.data);

  var task = tasks[data.task_id];

  task.total_jobs = data.total_jobs;

  update_progress(task);
}

function init_new_task() {
  $("#new_task_link").click(function (e) {
    $(".popup_window").hide();
    $("#click_catcher, #new_task").css({display: 'block'});

    /* reset to default state */
    $("#new_task .setup, #new_task .setup .if_empty").show();
    $("#new_task .setup .if_not_empty, #new_task .configure").hide();
    $("#new_task .configure .producer_form").empty();
    $("#new_task select option").prop("selected", false);
    $("#new_task select option:first").prop("selected", true);
    $("#new_task input").val("");
    $("#new_task input:checked").prop("checked", false);
    $("#new_task input[name='name']").focus();

    setTimeout(function () {
      $("#click_catcher, #new_task").addClass("show");
    }, 0);

    e.stopPropagation();
  });

  $("#new_task .create_button").click(function (e) {
    $.post('/tasks', $("#new_task form").serialize(), function (response) {
      localStorage["task_secret_info:" + response.id] = JSON.stringify(response);

      if (tasks.hasOwnProperty(response.id)) {
        select_task(tasks[response.id]);
      } else {
        created_task_id = response.id;
      }

      $("#click_catcher, #new_task").removeClass("show");
      setTimeout(function () {
        $("#click_catcher, #new_task").css({display: ''})
      }, popup_window_transition_duration);
    });
  });

  $("#new_task select[name='producer']").change(function (e) {
    if ($(this).val() === '') {

      $("#new_task .setup .if_empty")    .show();
      $("#new_task .setup .if_not_empty").hide();
    } else {

      $("#new_task .setup .if_empty")    .hide();
      $("#new_task .setup .if_not_empty").show();
    }
  });

  $("#new_task .configure_button").click(function (e) {
    $.get("/producer/" +
      $("#new_task select[name='producer']").val() + "/form",

      function (form) {

        $("#new_task .configure .producer_form").html(form);
        $("#new_task .configure").show();
        $("#new_task .setup").hide();
      });
  });
}

function task_produce_link(e) {
  $(".popup_window").hide();
  $("#click_catcher, #task_produce").css({display: 'block'});

  /* reset to default state */
  $("#task_produce .setup, #task_produce .setup .if_empty").show();
  $("#task_produce .setup .if_not_empty, #task_produce .configure").hide();
  $("#task_produce .configure .producer_form").empty();
  $("#task_produce select option").prop("selected", false);
  $("#task_produce select option:first").prop("selected", true);
  $("#task_produce input").val("");
  $("#task_produce input:checked").prop("checked", false);
  $("#task_produce input[name='name']").focus();

  setTimeout(function () {
    $("#click_catcher, #task_produce").addClass("show");
  }, 0);

  e.stopPropagation();
}

function init_task_produce() {
  $("#task_produce_link").click(task_produce_link);

  $("#task_produce .produce_button").click(function (e) {
    $.post('/task/' + task_secret_info(selected_task_id).secret + '/produce',
      $("#task_produce form").serialize(),

      function (response) {
        $("#click_catcher, #task_produce").removeClass("show");
        setTimeout(function () {
          $("#click_catcher, #task_produce").css({display: ''})
        }, popup_window_transition_duration);
      });
  });

  $("#task_produce select[name='producer']").change(function (e) {
    if ($(this).val() === '') {

      $("#task_produce .configure_button").prop('disabled', true);
    } else {

      $("#task_produce .configure_button").prop('disabled', false);
    }
  });

  $("#task_produce .configure_button").click(function (e) {
    $.get("/producer/" +
      $("#task_produce select[name='producer']").val() + "/form",

      function (form) {

        $("#task_produce .configure .producer_form").html(form);
        $("#task_produce .configure").show();
        $("#task_produce .setup").hide();
      });
  });
}

$(function() {
  // establish event source
  event_source = new EventSource("/tasks.event-stream");

  event_source.addEventListener("reload",       tasks_reload);
  event_source.addEventListener("taskcreated",  tasks_taskcreated);
  event_source.addEventListener("jobsubmitted", tasks_jobsubmitted);
  event_source.addEventListener("changetotal",  tasks_changetotal);

  // register actions
  $("#click_catcher").click(function() {
    $("#click_catcher, .popup_window").removeClass("show");
    setTimeout(function () {
      $("#click_catcher, .popup_window").css({display: ''});
    }, popup_window_transition_duration);
  });
  $(".popup_window").click(function (e) {
    e.stopPropagation();
  });

  init_new_task();
  init_task_produce();
});
