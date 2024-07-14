package Isomaker;
use Mojo::Base 'Mojolicious', -signatures;

use Mojo::File qw(path);
use Mojo::Util qw(slugify);

# This method will run once at server start
sub startup ($self) {

  $self->app->log->path($self->app->home->child('log')->make_path->child($self->app->mode.'.log'));

  # Load configuration from config file
  my $config = $self->plugin('NotYAMLConfig' => {default => {
    disc_path => '/dev/sr0',
    iso_path => $self->app->home->child('isos')->make_path,
    backup_path => $self->app->home->child('backups')->make_path,
  }});
  $self->plugin('Minion' => {SQLite => 'isomaker.db'});
  $self->plugin('Minion::Admin');

  $self->app->minion->add_task(
    make_iso => sub ($job, $name, $mkiso=1, $mkcp=0) {
      my $disc = path($job->app->config->{disc_path});
      my $iso = path($job->app->config->{iso_path})->child(slugify($name).'.iso');
      my $backup = path($job->app->config->{backup_path})->child(slugify($name));
      chomp(my $mnt = qx(df $disc | tail -1));
      $job->app->log->info($mnt);
      my @mnt = split /\s+/, $mnt, 6;
      $mnt = $mnt[-1];
      return $job->fail("$disc disc not found") unless $disc && -e $disc;
      $job->note(progress => 0);
      if ($mkiso) {
        warn "Making iso $name";
        $job->app->log->info("Making iso $iso");
        warn qx(dd if=$disc of="$iso" bs=2048 count=\$(isosize -d 2048 $disc) status=progress 2>&1) unless -e $iso; # TODO: report progress
        $job->app->log->info("Done making iso $iso");
	$job->note(progress => 50);
      }
      $job->app->log->info("Backing up mounted '$mnt'");
      if ($mkcp && $mnt && -d $mnt && -r $mnt) {
        warn "Making backup $name of $mnt";
        $mnt = path($mnt)->make_path;
        warn qx(cp -a "$mnt" $backup 2>&1 && echo "cp done") unless -e $backup; # TODO: report progress
        $job->app->log->info("Done making backup $backup");
	$job->note(progress => 100);
      }
      $job->app->log->info("Finished job $name");
      if (my $progress = $job->info->{notes}{progress}) {
        $job->finish("Completed $progress% of $name");
      }
      else {
        $job->fail("Could not read disc for $name");
      }
    }
  );

  # Configure the application
  $self->secrets($config->{secrets});

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('Isomaker#welcome')->name('welcome');
  $r->post('/')->to('Isomaker#make')->name('isomaker');
  my $conn = {};
  $r->websocket('/busy' => sub ($c) {
    $conn->{$c} = $c;
    $c->on(finish => sub ($c, $code, $reason = undef) {
      $c->app->log->debug("WebSocket closed with status $code");
      delete $conn->{$c};
    });
  });

  Mojo::IOLoop->recurring(1 => sub {
    foreach (map { $conn->{$_} } keys %$conn) {
      my $busy = $_->app->minion->jobs({states => ['active', 'inactive'], tasks => ['make_iso']})->total ? "Busy" : "NOT Busy";
      $_->send($busy);
    }
  });
}

1;
