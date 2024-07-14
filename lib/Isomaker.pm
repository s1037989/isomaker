package Isomaker;
use Mojo::Base 'Mojolicious', -signatures;

use Mojo::File qw(path);
use Mojo::Util qw(slugify);

# This method will run once at server start
sub startup ($self) {

  # Load configuration from config file
  my $config = $self->plugin('NotYAMLConfig' => {default => {
    disc_path => '/dev/sr0',
    out_path => '/tmp',
  }});
  $self->plugin('Minion' => {SQLite => 'isomaker.db'});
  $self->plugin('Minion::Admin');

  $self->app->minion->add_task(
    make_iso => sub ($job, $name) {
      my $disc = path($job->app->config->{disc_path});
      my $out = path($job->app->config->{out_path})->child(slugify($name).'.iso');
      return $job->fail("$disc disc not found") unless -e $disc;
      warn "Making iso $name";
      $job->app->log->info("Making iso $out");
      warn "dd if=$disc of=$out bs=2048 count=\$(isosize -d 2048 $disc) status=progress\n";
      sleep 5;
      $job->app->log->info("Done making iso $out");
      $job->finish($out);
    }
  );

  # Configure the application
  $self->secrets($config->{secrets});

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('Isomaker#welcome')->name('welcome');
  $r->post('/')->to('Isomaker#make')->name('isomaker');
}

1;
