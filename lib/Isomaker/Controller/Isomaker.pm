package Isomaker::Controller::Isomaker;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub make ($self) {
  if ($self->app->minion->jobs({states => ['active', 'inactive'], tasks => ['make_iso']})->total) {
    return $self->flash(msg => 'There is already an iso being made')->redirect_to('welcome');
  }
  my $name = $self->param('name');
  $self->app->minion->enqueue(make_iso => [$name, 1, 1]);
  $self->flash(msg => "Queued isomaker for $name")->redirect_to('welcome');
}

# This action will render a template
sub welcome ($self) {

  # Render template "isomaker/welcome.html.ep" with message
  $self->render(msg => 'Isomaker');
}

1;
